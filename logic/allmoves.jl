"converts a single board sqaure to a bitboard"
function to_UInt64(val)
    return UInt64(1) << val
end

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
test_king()
save_moves(king,king)


