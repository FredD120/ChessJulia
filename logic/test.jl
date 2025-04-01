using logic

const FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

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
    @assert board.WPawn != UInt64(0)
    @assert board.BPawn != UInt64(0)
    @assert board.BKing == UInt64(1) << 4
    @assert board.WKing == UInt64(1) << 60
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

function test_colour_pieces()
    board = Boardstate(FEN)
    white = white_pieces(board)
    black = black_pieces(board)
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
test_colour_pieces()

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
    wpieces = white_iterator(board)
    @assert length(wpieces) == 6
    @assert typeof(wpieces) == typeof(Vector{UInt64}())
    bpieces = black_iterator(board)
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

function test_currplayerinfo()
    board = Boardstate(FEN)
    iter, enemy, all = current_player_info(board)

    @assert length(iter) == 6
    @assert length(identify_locations(enemy)) == 16
    @assert length(identify_locations(all)) == 32
end
test_currplayerinfo()

function test_movegetters()
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    all_move_BBs = Move_BB()
    moves = generate_moves(board,all_move_BBs)

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

println("All tests passed")
