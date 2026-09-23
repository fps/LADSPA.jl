"""
A module for loading and running LADSPA plugins from Julia code.

# Examples

Find the plugin with label "AmpVTS" in the system:

```julia
d = filter(x -> unsafe_string(unsafe_load(x).Label) == "AmpVTS", LADSPA.descriptors())[1]
```

And instantiate it:

```julia
p = LADSPA.instantiate(d, 48000)
```

Create some buffers for it and connect them to the instance.

```julia
buffers = [zeros(Float32, 64) for n in 1:unsafe_load(d).PortCount]
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
    PortDescriptors::Ptr{Cvoid}
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

Connect a port of an instance of a plugin to a buffer (e.g. Vector{Float32})
"""
connect_port(descriptor, instance, port_index, buffer) = ccall(unsafe_load(descriptor).connect_port, Cvoid, (Ptr{Cvoid}, Culong, Ptr{Float32}), instance, port_index, buffer)

export connect_port


"""
    run(descriptor, instance, sample_count)

Run the ladspa plugin instance for the given sample count. Make sure all buffers are connected before calling this.
"""
run(descriptor, instance, sample_count) = ccall(unsafe_load(descriptor).run, Cvoid, (Ptr{Cvoid}, Culong), instance, sample_count)

export run

end
