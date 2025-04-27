"converts a single board sqaure to a bitboard"
function to_UInt64(val)
    return UInt64(1) << val
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

function generate_blocker_lengths(rank,file)
    Lu = max(rank-1,0)
    Ld = max(6-rank,0)
    Ll = max(file-1,0)
    Lr = max(6-file,0)
    return Lu,Ld,Ll,Lr
end

function Int_to_Arrays(INT,Lu,Ld,Ll,Lr)
    up = zeros(Lu)
    down = zeros(Ld)
    left = zeros(Ll)
    right = zeros(Lr)
end

function rook_move_BBs(pos = 0)
    file = pos % 8
    rank = (pos - file)/8 

    Lu,Ld,Ll,Lr = generate_blocker_lengths(rank,file)

    BB_lookup = Dict{UInt64,UInt64}()
    for i in UInt16(0):UInt16(2^12-1)
        println(i)
        BB = UInt64(0)
        counter = 0

        #move right
        cur_file = file
        fill_mode = false
        while (cur_file <= 6) & (fill_mode == false)
            cur_file += 1
            BB = set_location(rank,cur_file,BB)
            if i & (UInt16(0) << counter) == 0  #no blocker
                if cur_file == 6
                    BB = set_location(rank,cur_file+1,BB)
                end
                counter += 1
            else
                fill_mode = true
                counter += 7 - cur_file
            end
        end

        #move down
        cur_rank = rank
        fill_mode = false
        while (cur_rank <= 6) & (fill_mode == false)
            cur_rank += 1
            BB = set_location(cur_rank,file,BB)
            if i & (UInt16(0) << counter) == 0  #no blocker
                if cur_rank == 6
                    BB = set_location(cur_rank+1,file,BB)
                end
                counter += 1
            else
                fill_mode = true
                counter += 7 - cur_rank
            end
        end

        push!(BB_lookup,BB)
    end
    return BB_lookup
end

println(rook_move_BBs())