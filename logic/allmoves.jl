using JLD2

"converts a single board sqaure to a bitboard"
function to_UInt64(val)
    return UInt64(1) << val
end

"convert a position from number 0-63 to rank/file notation"
function UCIpos(pos)
    file = pos % 8
    rank = 8 - (pos - file)/8 
    return ('a'+file)*string(Int(rank))
end

"sets a bit in a bitboard"
setone(num::UInt64,index::Integer) = num | (UInt64(1) << index)

"convert chessboard x y to 1D array"
board_coords(x) =  x[1]*8 + x[2]

"Returns true if inbounds. For chessboards, limit=1, upper=7, lower=0"
function in_grid(val,upper,lower,limit=0)
    for (v,u,l) in zip(val,upper,lower)
        if !(v+limit > l && v-limit < u)
            return false
        end
    end
    return true
end

"save move data to file"
function save_data(data,filename)
    if isfile(filename)
        println("error creating $(filename): file already exists")
    else
        io = open(filename, "w") do io
            for d in data
            println(io, d)
            end
        end
    end
end

"save sliding piece dicts to file"
function save_dict(data,path,filename)
    if isfile(path*filename)
        println("error creating $(filename): file already exists")
    else
        jldopen(path*filename, "w") do file
            file["filename"] = data
        end
    end
end


"scan through chess squares, generating moves of a particular piece on that square"
function create_moves(f)
    chesspos = 0:7
    movelist = []
    for i in chesspos
        for j in chesspos
            moves = f(i,j)
            movelist = push!(movelist,moves)
        end
    end
    return movelist
end

"generate moves of a king at x,y"
function king(x,y)
    dirs = [-1,0,1]
    move_pos = UInt64(0)

    for i in dirs
        for j in dirs
            newcoords = [x + i,y + j]
            if in_grid(newcoords,[7,7],[0,0],1) & ((i != 0) | (j != 0))
                BB = to_UInt64(board_coords(newcoords))
                move_pos |= BB
            end
        end
    end
    return move_pos
end

"take generated moves and send them to be saved to a file"
function save_moves(f,filename)
    moves = create_moves(f)
    save_data(moves,"$(pwd())/logic/move_BBs/$(filename).txt")
end


function test_king()
    num1 = king(0,0)
    num2 = UInt64(1) << 1 | UInt64(1) << 8 | UInt64(1) << 9
    @assert num1 == num2
end
#test_king()
#save_moves(king,king)


### MAGIC BITBOARDS ###

function set_location(rank,file,BB)
    location = Int(rank*8 + file)
    return setone(BB,location)
end

function generate_rook_blocker_lengths(rank,file)
    Lu = Int(max(rank-1,0))
    Ld = Int(max(6-rank,0))
    Ll = Int(max(file-1,0))
    Lr = Int(max(6-file,0))
    return Lu,Ld,Ll,Lr
end

function Int_to_Arrays(INT,Lu,Ld,Ll,Lr)
    up = zeros(Lu)
    down = zeros(Ld)
    left = zeros(Ll)
    right = zeros(Lr)

    i=1
    while i <= Lu
        if INT & (UInt(1) << (i-1)) != 0
            up[i] = 1
        end
        i+=1
    end
    while i <= Lu+Ll
        if INT & (UInt(1) << (i-1)) != 0
            left[i-Lu] = 1
        end
        i+=1
    end
    while i <= Lu + Ll + Lr
        if INT & (UInt(1) << (i-1)) != 0
            right[i-Lu-Ll] = 1
        end
        i+=1
    end
    while i <= Lu + Ll + Lr + Ld
        if INT & (UInt(1) << (i-1)) != 0
            down[i-Lu-Ll-Lr] = 1
        end
        i+=1
    end
    return up,down,left,right
end

function get_key(up,down,left,right,rank,file)
    KEY = UInt64(0)

    for (index,is_piece) in enumerate(up)
        cur_rank = rank - index
        if is_piece > 0
            KEY = set_location(cur_rank,file,KEY)
        end
    end
    for (index,is_piece) in enumerate(down)
        cur_rank = rank + index
        if is_piece > 0
            KEY = set_location(cur_rank,file,KEY)
        end
    end
    for (index,is_piece) in enumerate(left)
        cur_file = file - index
        if is_piece > 0
            KEY = set_location(rank,cur_file,KEY)
        end
    end
    for (index,is_piece) in enumerate(right)
        cur_file = file + index
        if is_piece > 0
            KEY = set_location(rank,cur_file,KEY)
        end
    end
    return KEY
end

function get_sliding_moves(move_arr,pos,dirs)
    BB = UInt64(0)

    for (i,dir) in enumerate(dirs)
        fill = false
        for (index,is_piece) in enumerate(move_arr[i])
            cur_pos = pos + dir*index
            if fill == false
                BB = set_location(cur_pos[1],cur_pos[2],BB)
            end
            if is_piece > 0
                fill = true
            end
        end
        #deal with edge of the board, only if no blockers found so far
        cur_pos = pos + dir*(length(move_arr[i])+1)
        if in_grid(cur_pos,[7,7],[0,0],1) & (fill==false)
            BB = set_location(cur_pos[1],cur_pos[2],BB)
        end
    end
    return BB
end

function sliding_move_BBs(pos,piece)
    file = pos % 8
    rank = (pos - file)/8 

    Lu,Ld,Ll,Lr = (0,0,0,0)
    dirs = []
    if piece == "Rook"
        dirs = [[-1,0],[+1,0],[0,-1],[0,+1]]
        Lu,Ld,Ll,Lr = generate_rook_blocker_lengths(rank,file)
    elseif piece == "Bishop"
        dirs = [[+1,+1],[-1,-1],[+1,-1],[-1,+1]]
        println(piece)
    end

    BB_lookup = Dict{UInt64,UInt64}()

    #get mask to extract keys
    sq_mask = get_key(ones(Lu),ones(Ld),ones(Ll),ones(Lr),rank,file)

    for INT in UInt16(0):UInt16(2^(Lu+Ld+Ll+Lr)-1)
        up,down,left,right = Int_to_Arrays(INT,Lu,Ld,Ll,Lr)
        BBKey = get_key(up,down,left,right,rank,file)

        BBValue = get_sliding_moves([up,down,left,right],[rank,file],dirs)

        BB_lookup[BBKey] = BBValue
    end
    return BB_lookup,sq_mask
end

function all_sliding_moves(piece)
    filename = "$(piece)_dicts"
    sq_masks = Vector{UInt64}()
    lookups =  Vector{Dict{UInt64,UInt64}}()
    for pos in 0:63
        dict,mask = sliding_move_BBs(pos,piece)
        
        push!(lookups,dict)
        push!(sq_masks,mask)
    end
    #save_data(sq_masks,"$(pwd())/logic/move_BBs/$(piece)Masks.txt")
    save_dict(lookups,"$(pwd())/logic/move_BBs/","$(filename).jld2")
end
all_sliding_moves("Rook")

