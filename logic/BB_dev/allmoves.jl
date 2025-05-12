#using JLD2
using logic

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
            file["data"] = data
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

function generate_bishop_blocker_lengths(rank,file)
    Lu = Int(max(min(rank-1,file-1),0))
    Ld = Int(max(min(6-rank,6-file),0))
    Ll = Int(max(min(6-rank,file-1),0))
    Lr = Int(max(min(rank-1,6-file),0))
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

function get_key(move_arr,pos,dirs)
    KEY = UInt64(0)

    for (i,dir) in enumerate(dirs)
        for (index,is_piece) in enumerate(move_arr[i])

            cur_pos = pos + dir*index
            if is_piece > 0
                KEY = set_location(cur_pos[1],cur_pos[2],KEY)
            end
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
        dirs = [[-1,-1],[+1,+1],[+1,-1],[-1,+1]]
        Lu,Ld,Ll,Lr = generate_bishop_blocker_lengths(rank,file)
    end

    BB_lookup = Dict{UInt64,UInt64}()

    #get mask to extract keys
    sq_mask = get_key([ones(Lu),ones(Ld),ones(Ll),ones(Lr)],[rank,file],dirs)

    for INT in UInt16(0):UInt16(2^(Lu+Ld+Ll+Lr)-1)
        up,down,left,right = Int_to_Arrays(INT,Lu,Ld,Ll,Lr)
        BBKey = get_key([up,down,left,right],[rank,file],dirs)

        BBValue = get_sliding_moves([up,down,left,right],[rank,file],dirs)

        BB_lookup[BBKey] = BBValue
    end
    return BB_lookup,sq_mask
end

function magic(BB,num,N)
    return (BB*num) >> (64-N)
end

function check_magic(dict,mag,N)
    arr = zeros(UInt64,2^N)
    for (key,val) in dict
        ind = magic(key,mag,N) + 1
        if arr[ind] == 0
            arr[ind] = val
        elseif arr[ind] != val
            return false
        end
    end
    println("Found:$mag")
    return true
end

function find_magic(dict,hints=[])
    N = Int(log(2,length(dict))) 

    cur_max = 0
    for (key,val) in dict
        if key > cur_max
            cur_max = key
        end
    end
    lsb_max = trailing_zeros(cur_max)

    if length(hints)>0
    for h in hints
        if check_magic(dict,h,N-1) 
            return h,(N-1)
        end
        if check_magic(dict,h,N) 
            return h,N
        end
    end
    end

    #=Threads.@threads=# for _ in 1:100_000_000
        #g = rand((UInt64(1) << (64-N-lsb_max)):(UInt64(1) << (64-lsb_max)))

        g = rand(UInt64) & rand(UInt64) & rand(UInt64)
        if count_ones(g) > 6 
            if check_magic(dict,g,N) 
                return g,N
            end
        end
    end
    return UInt64(0),N
end

function all_sliding_moves(piece)
    sq_masks = Vector{UInt64}()
    magics = Vector{UInt64}()
    Shifts = Vector{UInt64}()
    lookups =  Vector{Dict{UInt64,UInt64}}()
    hints = logic.read_txt("hints")
    
    for pos in 0:63
        dict,mask = sliding_move_BBs(pos,piece)
        
        push!(lookups,dict)
        push!(sq_masks,mask)

        println("currently searching $pos")
        magNum,shift = find_magic(dict,hints)
        push!(magics,magNum)
        push!(Shifts,shift)
    end
    #save_data(sq_masks,"$(pwd())/logic/move_BBs/$(piece)Masks.txt")
    save_data(magics,"$(pwd())/logic/move_BBs/$(piece)Magics.txt")
    save_data(Shifts,"$(pwd())/logic/move_BBs/$(piece)BitShifts.txt")
    #save_dict(lookups,"$(pwd())/logic/move_BBs/","$(piece)_dicts.jld2")
end
#all_sliding_moves("Rook")

#Read in magics and construct array

function open_JLD2(filename)
    path = "$(pwd())/logic/move_BBs/"
    dicts = Vector{Dict{UInt64,UInt64}}()
    jldopen(path*filename*".jld2", "r") do file
        dicts = file["data"]
    end
    return dicts
end

function assemble_magic_array(mag,dict,N,square)
    arr = zeros(UInt64,2^N)
    keycount = 0
    for (key,val) in dict
        keycount+=1
        ind = magic(key,mag,N) + 1
        if arr[ind] == 0
            arr[ind] = val
        elseif arr[ind] != val
            println("Error at key $keycount and square $square")
            break
        end
    end
    return arr
end

function make_magic(piece)
    dictname = "$(piece)_dicts"
    dict_vec = open_JLD2(dictname)

    magicname = "$(piece)Magics"
    magics = logic.read_txt(magicname)

    maskname = "$(piece)Masks"
    masks = logic.read_txt(maskname)

    magic_arrays = Vector{Vector{UInt64}}()
    magic_shifts = logic.read_txt("$(piece)BitShifts")

    square = 0
    dict_length = 0
    array_length = 0
    for (dict,magic,shift) in zip(dict_vec,magics,magic_shifts)
        square+=1
        magic_array = assemble_magic_array(magic,dict,shift,square)
        push!(magic_arrays,magic_array)

        dict_length += length(dict)
        array_length += length(magic_array)
        println("Saved $piece square $square. Original dict had $(length(dict)) entries. Magic array has $(length(magic_array)) entries.")
    end
    println("Original dict size ≈ $(dict_length*8) bytes. Magic array size ≈ $(array_length*8) bytes.")
    jldsave("$(pwd())/logic/move_BBs/Magic$(piece)s.jld2",Masks=masks,Magics=magics,BitShifts=magic_shifts,AttackVec=magic_arrays)
end
#make_magic("Bishop")

function get_magic(piece,pos)
    dict,mask = sliding_move_BBs(pos,piece)
    println(find_magic(dict))
end

### Castling BBs ###

function make_castle_blockers()
    Kwhite = (UInt64(1) << 61) | (UInt64(1) << 62) 
    Qwhite = (UInt64(1) << 58) | (UInt64(1) << 59) 
    Kblack = (UInt64(1) << 5) | (UInt64(1) << 6) 
    Qblack = (UInt64(1) << 2) | (UInt64(1) << 3) 
    QWblock = Qwhite | (UInt64(1) << 57)
    QBblock = Qblack | (UInt64(1) << 1)
    return [Kwhite,Qwhite,Kblack,Qblack,QWblock,QBblock]
end

function save_castle()
    castlers = make_castle_blockers()
    for C in castlers
        println(bitstring(C))
    end
    save_data(castlers,"CastleCheck.txt")
end
save_castle()