"""
A module for loading and running LADSPA plugins from Julia code.

# Examples

Find the plugin with label "AmpVTS" in the system (this comes from the `caps.so` library):

```julia
d = filter(x -> unsafe_string(unsafe_load(x).Label) == "AmpVTS", LADSPA.descriptors())[1]
```

And instantiate it:

```julia
p = LADSPA.instantiate(d, 48000)
```

Create some buffers for it and connect them to the instance.

```julia
buffers = LADSPA.prepare_buffers(d, 64)

# Set some control port default values
defaults = [1, 0.25, 0.75, 0.5, 0, 0.25, 0.75, 1, 0.25, 0.75, 0.75]; [buffers[k] .= defaults[k] for k in 1:length(defaults)]

for n in 1:unsafe_load(d).PortCount
    LADSPA.connect_port(d, p, n-1, buffers[n])
end
```

Activate the instance (if required):

```julia
if unsafe_load(d).activate != C_NULL
    LADSPA.activate(d, p)
end
```

And finally run it for 64 frames:

```julia
LADSPA.run(d, p, 64)
```
"""
module LADSPA

import Libdl

"""
    path()

Get the list of directories from the LADSPA_PATH environment variable.
"""
path() = split(ENV["LADSPA_PATH"], ":")

export path


"""
    libraries(directories)

Get the list of shared libraries in the directories.

Example:

```julia
LADSPA.libraries(LADSPA.path())
```
"""
libraries(directories) = filter(
    x -> x[(end-(length(Libdl.dlext)-1)):end] == Libdl.dlext,
    vcat([p * "/" .* Base.Filesystem.readdir(p) for p in filter(Base.Filesystem.isdir, directories)]...))

export libraries


"""
A struct containing information about the range of values for a port.
"""
struct PortRangeHint
    HintDescriptor::Cint
    LowerBound::Cfloat
    UpperBound::Cfloat
end


"""
A structure mirroring the LADSPA_Descriptor C structure
"""
struct Descriptor
    UniqueID::Culong
    Label::Cstring
    Properties::Cint
    Name::Cstring
    Maker::Cstring
    Copyright::Cstring
    PortCount::Culong
    PortDescriptors::Ptr{Cint}
    PortNames::Ptr{Cstring}
    PortRangeHints::Ptr{PortRangeHint}
    ImplementationData::Ptr{Cvoid}

    instantiate::Ptr{Cvoid}
    connect_port::Ptr{Cvoid}
    activate::Ptr{Cvoid}
    run::Ptr{Cvoid}
    run_adding::Ptr{Cvoid}
    set_run_adding_gain::Ptr{Cvoid}
    deactivate::Ptr{Cvoid}
    cleanup::Ptr{Cvoid}
end



"""
A structure bundling a raw and an unsafe_load'ed descriptor together.
"""
struct LoadedDescriptor
    raw
    loaded
end



"""
A struct for bundling a LoadedDescriptor and an instance pointer together.
"""
struct Instance
    descriptor
    instance
end



"""
    label(descriptor)

Get the label of a plugin from a descriptor.
"""
label(descriptor) = unsafe_string(descriptor.loaded.Label)

export label


"""
    name(descriptor)

Get the name of a plugin from a descriptor
"""
name(descriptor) = unsafe_string(descriptor.loaded.Name)

export name


"""
    descriptors(lib)

Get the list of all LADSPA descriptors in a lib (lib has to be opened with Libdl.dlopen())
"""
function descriptors(lib)
    index = 0
    ds = []
    while true
        d = ccall(Libdl.dlsym(lib, "ladspa_descriptor"), Ptr{LADSPA.Descriptor}, (Int32,), index)
        if d == C_NULL
            break;
        end
        
        push!(ds, LoadedDescriptor(d, unsafe_load(d)))
        index += 1
    end
    ds
end


"""
    descriptors()

Find all LADSPA plugin descriptors on the system (uses LADSPA.libraries(LADSPA.path()) to find all LADSPA plugin libs on the system)
"""
descriptors() = vcat([descriptors(Libdl.dlopen(l)) for l in libraries(path())]...)

export descriptors


function port_name(descriptor, port_index)
    if !(port_index in 1:descriptor.loaded.PortCount)
        error("Port index out of bounds")
    end

    unsafe_string(unsafe_load(descriptor.loaded.PortNames, port_index))
end


function port_range_hint(descriptor, port_index)
    if !(port_index in 1:descriptor.loaded.PortCount)
        error("Port index out of bounds")
    end

    unsafe_load(descriptor.loaded.PortRangeHints, port_index)
end


function port_default(descriptor, port_index, samplerate)
    if !(port_index in 1:descriptor.loaded.PortCount)
        error("Port index out of bounds")
    end

    hint = port_range_hint(descriptor, port_index)

    hint_logarithmic = (hint.HintDescriptor & 0x10) != 0
    hint_samplerate = (hint.HintDescriptor & 0x8) != 0

    lower = hint.LowerBound
    uppert = hint.UpperBound

    if hint_samplerate
        lower *= samplerate
        upper *= samplerate
    end

    masked = hint.HintDescriptor & 0x3c0
    
    if masked == 0 # NO DEFAULT - DUNNO :)
        0f0
    elseif masked == 0x40 # DEFAULT_MINIMUM
        hint.LowerBound
    elseif masked == 0x80 # DEFAULT_LOW
        if hint_logarithmic
            exp(25f-2 * log(hint.UpperBound) + 75f-2 * log(hint.LowerBound))
        else
            (25f-2 * hint.UpperBound + 75f-2 * hint.LowerBound)
        end
    elseif masked == 0xc0 # DEFAULT_MIDDLE
        if hint_logarithmic
            exp((log(hint.UpperBound) + log(hint.LowerBound)) / 2)
        else
            (hint.UpperBound + hint.LowerBound) / 2
        end
    elseif masked == 0x100 # DEFAULT_HIGH
        if hint_logarithmic
            exp(75f-2 * log(hint.UpperBound) + 25f-2 * log(hint.LowerBound))
        else
            (75f-2 * hint.UpperBound + 25f-2 * hint.LowerBound)
        end
    elseif masked == 0x140 # DEFAULT_MAXIMUM
        hint.UpperBound
    elseif masked == 0x200 # DEFAULT_0
        0f0
    elseif masked == 0x240 # DEFAULT_1
        1f0
    elseif masked == 0x280 # DEFAULT_100
        100f0
    elseif masked == 0x2c0 # DEFAULT_$$)
        444f0
    else # DUNNO :)
        0f0
    end
end


"""
    instantiate(descriptor, samplerate)

Instantiate a plugin given a descriptor and a samplerate.
"""
instantiate(descriptor, samplerate) = Instance(
    descriptor,
    ccall(descriptor.loaded.instantiate, Ptr{Cvoid}, (Ptr{Descriptor}, Culong), descriptor.raw, samplerate))

export instantiate


"""
    activate(descriptor, instance)

Activate a plugin instance. Does nothing if the plugin has no activate function.
"""
function activate(instance)
    if instance.descriptor.loaded.activate != C_NULL
        ccall(instance.descriptor.loaded.activate, Cvoid, (Ptr{Cvoid},), instance.instance);
    end
end

export activate


"""
    connect_port(descriptor, instance, port_index, buffer)

Connect a port of an instance of a plugin to a buffer (e.g. Vector{Cfloat}). See also LADSPA.prepare_buffers.
"""
function connect_port(instance, port_index, buffer)
    if !(port_index in 1:instance.descriptor.loaded.PortCount)
        error("Port index out of bounds")
    end
        
    ccall(instance.descriptor.loaded.connect_port, Cvoid, (Ptr{Cvoid}, Culong, Ptr{Cfloat}), instance.instance, port_index, buffer)
end

export connect_port


"""
    run(descriptor, instance, sample_count)

Run the ladspa plugin instance for the given sample count. Make sure all buffers are connected before calling this.
"""
run(instance, sample_count) = ccall(instance.descriptor.loaded.run, Cvoid, (Ptr{Cvoid}, Culong), instance.instance, sample_count)


"""
    run(descriptor, instance, buffers, chunksize)

Run the LADSPA plugin instance over the given buffers with the given chunksize.
"""
function run(instance, buffers, chunksize)
    for n in 1:chunksize:(length(buffers[1]) - (chunksize-1))
        current_buffers = [@view buffers[k][n:(n+(chunksize-1))] for k in 1:length(buffers)]

        for p in 1:length(current_buffers)
            connect_port(instance, p-1, current_buffers[p])
        end
        
        run(instance, chunksize)
    end
end

export run


"""
    prepare_buffers(descriptor, length)

Prepare an array of buffers for a plugin.
"""
prepare_buffers(descriptor, length) = [ zeros(Cfloat, length) for n in 1:unsafe_load(descriptor).PortCount ]

export prepare_buffers


"""
    deactivate(instance)

Deactivate a plugin instance. Does nothing if the plugin does not have a deactivate function.
"""
function deactivate(instance)
    if instance.descriptor.loaded.deactivate != C_NULL
        ccall(instance.descriptor.loaded.deactivate, Cvoid, (Ptr{Cvoid},), instance.instance)
    end
end

export deactivate


"""
    cleanup(instance)

Cleanup a plugin instance. Does nothing if the plugin does not have a cleanup function.
"""
function cleanup(descriptor, instance)
    if instance.descriptor.loaded.cleanup != C_NULL
        ccall(instance.descriptor.loaded.cleanup, Cvoid, (Ptr{Cvoid},), instance.instance)
    end
end

export cleanup


"Indicates whether a port is an input port. See port_has_property"
PORT_INPUT = 1

"Indicates whether a port is an output port. See port_has_property"
PORT_OUTPUT = 2

"Indicates whether a port is a control rate port. See port_has_property"
PORT_CONTROL = 4

"Indicates whether a port is an audio rate port. See port_has_property"
PORT_AUDIO = 8

export PORT_INPUT
export PORT_OUTPUT
export PORT_CONTROL
export PORT_AUDIO


function port_descriptor(descriptor, port_index)
    if !(port_index in 1:descriptor.loaded.PortCount)
        error("Port index out of bounds")
    end

    unsafe_load(descriptor.loaded.PortDescriptors, port_index)
end



"""
    port_has_property(descriptor, port_index, property)

Check if a port has a property. See IS_PORT_INPUT, IS_PORT_OUTPUT, IS_PORT_CONTROL, IS_PORT_AUDIO)
"""
function port_has_property(descriptor, port_index, property)
    port_descriptor(descriptor, port_index) & property != 0
end

export port_has_property

end
