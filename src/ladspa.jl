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
    Libdl.LazyLibrary(path)
end

function descriptor(path, index)
    l = Libdl.dlopen(path)
    f = Libdl.dlsym(l, "ladspa_descriptor")
    d = ccall(f, Ptr{LADSPA.Descriptor}, (Int32,), 0)
    unsafe_load(d)
end

end
