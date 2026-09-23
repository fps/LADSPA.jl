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
defaults = [1, 0.25, 0.75, 0.5, 0, 0.25, 0.75, 1, 0.25, 0.75, 0.75]; [buffers[k][1] = defaults[k] for k in 1:length(defaults)]

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
    libs()

Get the list of shared libraries in the directories returned from path().
"""
libs() = filter(x -> x[(end-(length(Libdl.dlext)-1)):end] == Libdl.dlext, vcat([p * "/" .* Base.Filesystem.readdir(p) for p in filter(Base.Filesystem.isdir, path())]...))

export libs


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
    PortNames::Ptr{Cvoid}
    PortRangeHints::Ptr{Cvoid}
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
    descriptor(lib, index)

Get the LADSPA descriptor at index from lib (lib has to be opened with Libdl.dlopen())
"""
descriptor(lib, index) = ccall(Libdl.dlsym(lib, "ladspa_descriptor"), Ptr{LADSPA.Descriptor}, (Int32,), index)

export descriptor


"""
    descriptors(lib)

Get the list of all LADSPA descriptors in a lib (lib has to be opened with Libdl.dlopen())
"""
function descriptors(lib)
    index = 0
    ds = []
    while true
        d = descriptor(lib, index)
        if d == C_NULL
            break;
        end
        
        push!(ds, d)
        index += 1
    end
    ds
end


"""
    descriptors()

Find all LADSPA plugin descriptors on the system (uses libs() to find all LADSPA plugin libs on the system)
"""
descriptors() = vcat([descriptors(Libdl.dlopen(l)) for l in libs()]...)

export descriptors


"""
    instantiate(descriptor, samplerate)

Instantiate a plugin given a descriptor and a samplerate.
"""
instantiate(descriptor, samplerate) = ccall(unsafe_load(descriptor).instantiate, Ptr{Cvoid}, (Ptr{Descriptor}, Culong), descriptor, samplerate)

export instantiate


"""
    activate(descriptor, instance)

Activate a plugin instance. Call this only when unsafe_load(descriptor).activate != C_NULL.
"""
activate(descriptor, instance) = ccall(unsafe_load(descriptor).activate, Cvoid, (Ptr{Cvoid},), instance)

export activate


"""
    connect_port(descriptor, instance, port_index, buffer)

Connect a port of an instance of a plugin to a buffer (e.g. Vector{Cfloat})
"""
connect_port(descriptor, instance, port_index, buffer) = ccall(unsafe_load(descriptor).connect_port, Cvoid, (Ptr{Cvoid}, Culong, Ptr{Cfloat}), instance, port_index, buffer)

export connect_port


"""
    run(descriptor, instance, sample_count)

Run the ladspa plugin instance for the given sample count. Make sure all buffers are connected before calling this.
"""
run(descriptor, instance, sample_count) = ccall(unsafe_load(descriptor).run, Cvoid, (Ptr{Cvoid}, Culong), instance, sample_count)


"""
    run(descriptor, instance, buffers, chunksize)

Run the LADSPA plugin instance over the given buffers with the given chunksize.
"""
function run(descriptor, instance, buffers, chunksize)
    for n in 1:chunksize:(length(buffers[1]) - (chunksize-1))
        current_buffers = [@view buffers[k][n:(n+(chunksize-1))] for k in 1:length(buffers)]

        for p in 1:length(current_buffers)
            connect_port(descriptor, instance, p-1, current_buffers[p])
        end
        
        run(descriptor, instance, chunksize)
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
    deactivate(descriptor, instance)

Deactivate a plugin instance
"""
deactivate(descriptor, instance) = ccall(unsafe_load(descriptor).deactivate, Cvoid, (Ptr{Cvoid},), instance)

export deactivate


"""
    cleanup(descriptor, instance)

Cleanup a plugin instance
"""
cleanup(descriptor, instance) = ccall(unsafe_load(descriptor).cleanup, Cvoid, (Ptr{Cvoid},), instance)

export cleanup


IS_PORT_INPUT = 1
IS_PORT_OUTPUT = 2
IS_PORT_CONTROL = 4
IS_PORT_AUDIO = 8

export IS_PORT_INPUT
export IS_PORT_OUTPUT
export IS_PORT_CONTROL
export IS_PORT_AUDIO


"""
    port_has_property(descriptor, port_index, property)

Check if a port has a property. See IS_PORT_INPUT, IS_PORT_OUTPUT, IS_PORT_CONTROL, IS_PORT_AUDIO)
"""
port_has_property(descriptor, port_index, property) = port_index in 1:unsafe_load(descriptor).PortCount ? unsafe_load(unsafe_load(descriptor).PortDescriptors, port_index) & property != 0 : false

export port_has_property

end
