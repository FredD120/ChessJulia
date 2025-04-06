using logic

const FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const all_moves = Move_BB()

function test_setters()
    num = UInt64(1)

    num = setone(num,1)
    @assert num == UInt64(3)

    num = setzero(num,0)
    @assert num == UInt64(2)
end
test_setters()

function test_boardinit()
    board = Boardstate(FEN)
    @assert board.Whitesmove == true
    @assert board.EnPassant == UInt64(0)
    @assert board.ally_pieces[3] != UInt64(0)
    @assert board.enemy_pieces[3] != UInt64(0)
    @assert board.enemy_pieces[1] == UInt64(1) << 4
    @assert board.ally_pieces[1] == UInt64(1) << 60
    @assert board.Halfmoves == 0
end
test_boardinit()

function test_GUIboard()
    board = Boardstate(FEN)
    GUIboard = GUIposition(board)
    @assert typeof(GUIboard) == typeof(Vector{UInt8}())
    @assert length(GUIboard) == 64
    @assert GUIboard[5] == 7
end
test_GUIboard()

function test_player_pieces()
    board = Boardstate(FEN)
    white = player_pieces(board.ally_pieces)
    black = player_pieces(board.enemy_pieces)
    all = all_pieces(board)
    compareW = UInt64(0)
    compareB = UInt64(0)

    for i in 0:15
        compareW += UInt64(1) << (63-i)
        compareB += UInt64(1) << i
    end
    @assert white == compareW
    @assert black == compareB
    @assert all == compareW | compareB
end
test_player_pieces()

function test_moveBB()
    movestruct = Move_BB()
    @assert length(movestruct.knight) == 64
    @assert movestruct.king[1] == UInt64(770)
end
test_moveBB()

function test_iterators()
    board = Boardstate(FEN)
    pieces = piece_iterator(board)
    @assert length(pieces) == 12
    @assert typeof(pieces) == typeof(Vector{UInt64}())
    wpieces = board.ally_pieces
    @assert length(wpieces) == 6
    @assert typeof(wpieces) == typeof(Vector{UInt64}())
    bpieces = board.enemy_pieces
    @assert length(bpieces) == 6
    @assert typeof(bpieces) == typeof(Vector{UInt64}())
end
test_iterators()

function test_determinepiece()
    func = determine_piece(1)
    @assert typeof(func) == typeof(get_kingmoves)
end 
test_determinepiece()

function test_identifylocs()
    BB = UInt64(1) << 15 | UInt64(1) << 10
    locs = identify_locations(BB)
    @assert length(locs) == 2
    @assert locs[1] * locs[2] == 150
end
test_identifylocs()

function test_movfromloc()
    moves = moves_from_location(UInt64(3),2,false)
    @assert length(moves) == 2
    @assert moves[1].iscapture == false
    @assert moves[2].from == 2
end
test_movfromloc()

function test_kingmoves()
    moves = get_kingmoves(UInt8(0),all_moves,UInt64(0),UInt64(0))
    @assert length(moves) == 3

end
test_kingmoves()

function test_movegetters()
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = generate_moves(board,all_moves)

    attks = 0
    quiets = 0
    for m in moves 
        if m.iscapture
            attks+=1
        else 
            quiets+=1
        end
    end
    @assert attks == 1
    @assert quiets == 7
end
test_movegetters()

function test_makemove()
    basicFEN = "K7/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board,all_moves)

    @assert board.ally_pieces[1] == UInt64(1)

    for m in moves
        if m.to == 1
            make_move!(m,board,1)
        end
    end

    @assert board.Whitesmove == false
    @assert board.Halfmoves == UInt32(1)
    @assert board.enemy_pieces[1] == UInt64(2)
end
test_makemove()

println("All tests passed")
