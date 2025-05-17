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

function readPerft(depth)
    FENs = String[]
    Depths = Int[]
    Targets = Int[]

    data_str = readlines("$(dirname(@__DIR__))/BB_dev/perftsuite.txt")
    for d in data_str
        arr = split(d," ;")
        push!(FENs, arr[1])

        depth = min(depth,length(arr)-1)
        leaves = split(arr[depth+1])[end]
        
        push!(Targets,parse(Int,leaves))
        push!(Depths,depth)
    end   
    return FENs,Depths,Targets
end

function perft_suite(dep)
    Δt = 0
    leaves = 0
    FENs,Depths,Targets = readPerft(dep)

    for (FEN,depth,target) in zip(FENs,Depths,Targets)
        board = Boardstate(FEN)
        if verbose
            println("Testing position: $FEN")
        end
        t = time()
        cur_leaves = perft(board,depth,true)
        Δt += time() - t
        leaves += cur_leaves

        @assert cur_leaves == target "failed on FEN $FEN, missing $(target-cur_leaves) nodes"
    end
    println("Perft complete. Total leaf nodes found: $leaves. NPS = $(leaves/Δt) nodes/second")
end

function single_perft(FEN,depth)
    board = Boardstate(FEN)
    t = time()
    leaves = perft(board,depth,true)
    Δt = time() - t
    println("Perft complete. Total nodes = $leaves NPS = $(leaves/Δt)")
end

function main()
    #comparePerft()
    #perft_suite(6)
    single_perft("nnnnknnn/8/8/8/8/8/8/NNNNKNNN w KQkq - 0 1",5)
end
main()

