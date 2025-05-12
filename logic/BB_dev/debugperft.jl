function readtxt(filename)
    data = Dict{String,Int}()
    data_str = readlines("$(dirname(@__DIR__))/BB_dev/$(filename).txt")
    for d in data_str
        karr = split(d,": ")
        #println("key:$(karr[1]) val:$(karr[2])")
        data[karr[1]] = parse(Int,karr[2])
    end   
    return data
end

Juliadict = readtxt("Julia")
Sfishdict = readtxt("Stockfish")

#@assert length(Juliadict) == length(Sfishdict)

for (Jkey,Jval) in Juliadict
    if haskey(Sfishdict,Jkey)
        if Sfishdict[Jkey] != Jval
            println("Nodes don't match $Jkey: diff = $(Sfishdict[Jkey] - Jval)")
        end
    else
        println("Move doesn't match: $Jkey")
    end
end

