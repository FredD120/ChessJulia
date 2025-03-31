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
    compareW = UInt64(0)
    compareB = UInt64(0)

    for i in 0:15
        compareW += UInt64(1) << (63-i)
        compareB += UInt64(1) << i
    end
    @assert white == compareW
    @assert black == compareB
end
test_colour_pieces()

function test_moves()
    movestruct = Moves()
    @assert length(movestruct.knight) == 64
end
test_moves()

println("All tests passed")
