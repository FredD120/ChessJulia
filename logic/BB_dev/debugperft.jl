using logic
const verbose = true

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

function comparePerft()
    Juliadict = readtxt("Julia")
    Sfishdict = readtxt("Stockfish")

    for (Jkey,Jval) in Juliadict
        if haskey(Sfishdict,Jkey)
            if Sfishdict[Jkey] != Jval
                println("Nodes don't match $Jkey: diff = $(Sfishdict[Jkey] - Jval)")
            end
        else
            println("Move doesn't match: $Jkey")
        end
    end
end
#comparePerft()

function readPerft(depth)
    data = Dict{String,Int}()
    data_str = readlines("$(dirname(@__DIR__))/BB_dev/perftsuite.txt")
    for d in data_str
        arr = split(d," ;")
        FEN = arr[1]
        leaves = split(arr[depth+1])[end]
        
        data[FEN] = parse(Int,leaves)
    end   
    return data
end

function perft_suite(depth)
    Δt = 0
    leaves = 0
    perft_dict = readPerft(depth)

    for (FEN,target) in perft_dict
        board = Boardstate(FEN)
        if verbose
            println("Testing position: $FEN")
        end
        t = time()
        cur_leaves = perft(board,depth)
        Δt += time() - t
        leaves += cur_leaves

        @assert cur_leaves == target "failed on FEN $FEN, missing $(target-cur_leaves) nodes"
    end
    println("Perft complete. Total leaf nodes found: $leaves. NPS = $(leaves/Δt) nodes/second")
end
perft_suite(2)