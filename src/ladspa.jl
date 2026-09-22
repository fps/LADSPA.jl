module LADSPA

import Libdl

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

function load_library(path)
    Libdl.dlopen(path)
end

function descriptor(lib, index)
    f = Libdl.dlsym(lib, "ladspa_descriptor")
    d = ccall(f, Ptr{LADSPA.Descriptor}, (Int32,), index)
    (d, unsafe_load(d))
end

function instantiate(descriptor, samplerate)
    ccall(unsafe_load(descriptor).instantiate, Ptr{Cvoid}, (Ptr{Descriptor}, Culong), descriptor, samplerate)
end

function activate(descriptor, instance)
    ccall(unsafe_load(descriptor).activate, Cvoid, (Ptr{Cvoid},), instance)
end

function connect_port(descriptor, instance, port_index, buffer)
    ccall(unsafe_load(descriptor).connect_port, Cvoid, (Ptr{Cvoid}, Culong, Ptr{Float32}), instance, port_index, buffer)
end

function run(descriptor, instance, sample_count)
    ccall(unsafe_load(descriptor).run, Cvoid, (Ptr{Cvoid}, Culong), instance, sample_count)
end

end
