using logic

const FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

function test_setters()
    num = UInt64(1)

    num = logic.setone(num,1)
    @assert num == UInt64(3)

    num = logic.setzero(num,0)
    @assert num == UInt64(2)
    num = logic.setzero(num,1)
    @assert num == UInt64(0)

    num2 = UInt64(2)
    @assert logic.setzero(num2,8) == UInt64(2)
end
test_setters()

function test_boardinit()
    board = Boardstate(FEN)
    @assert Whitesmove(board) == true
    @assert board.EnPassant == UInt64(0)
    @assert logic.ally_pieces(board)[3] != UInt64(0)
    @assert logic.enemy_pieces(board)[3] != UInt64(0)
    @assert logic.enemy_pieces(board)[1] == UInt64(1) << 4
    @assert logic.ally_pieces(board)[1] == UInt64(1) << 60
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
    white = logic.player_pieces(logic.ally_pieces(board))
    black = logic.player_pieces(logic.enemy_pieces(board))
    all = logic.player_pieces(board.pieces)
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
    movestruct = logic.Move_BB()
    @assert length(movestruct.knight) == 64
    @assert movestruct.king[1] == UInt64(770)
end
test_moveBB()

function test_iterators()
    board = Boardstate(FEN)
    pieces = board.pieces
    @assert length(pieces) == 12
    pieces::Matrix{UInt64}
    wpieces = logic.ally_pieces(board)
    @assert length(wpieces) == 6
    @assert typeof(wpieces) == typeof(Vector{UInt64}())
    bpieces = logic.enemy_pieces(board)
    @assert length(bpieces) == 6
    @assert typeof(bpieces) == typeof(Vector{UInt64}())
end
test_iterators()

function test_identifylocs()
    BB = UInt64(1) << 15 | UInt64(1) << 10
    locs = logic.identify_locations(BB)
    @assert length(locs) == 2
    @assert locs[1] * locs[2] == 150
end
test_identifylocs()

function test_movfromloc()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = logic.moves_from_location(UInt8(1),board,UInt64(3),2,UInt64(0),false)
    @assert length(moves) == 2
    @assert moves[1].capture_type == 0
    @assert moves[2].from == 2
    @assert moves[1].piece_type == 1
end
test_movfromloc()

function test_kingmoves()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = logic.get_kingmoves(UInt8(0),board,UInt64(0),UInt64(0),UInt64(0))
    @assert length(moves) == 3
end
test_kingmoves()

function test_knightmoves()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = logic.get_knightmoves(UInt8(0),board,UInt64(0),UInt64(0),UInt64(0))
    @assert length(moves) == 2
end
test_knightmoves()

function test_movegetters()
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = generate_moves(board)

    attks = 0
    quiets = 0
    for m in moves 
        if m.capture_type > 0 
            attks+=1
        else 
            quiets+=1
        end
    end
    @assert attks == 1
    @assert quiets == 5

    simpleFEN = "8/8/4nK2/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    board.Halfmoves = 100
    moves = generate_moves(board)
    @assert length(moves) == 0
    @assert board.State == Draw()
end
test_movegetters()

function test_makemove()
    #Test making a move with only one piece on the board
    basicFEN = "K7/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    @assert logic.ally_pieces(board)[1] == UInt64(1)

    for m in moves
        if m.to == 1
            make_move!(m,board)
        end
    end

    @assert Whitesmove(board) == false
    @assert board.Halfmoves == UInt32(1)
    @assert logic.enemy_pieces(board)[1] == UInt64(2)

    #Test making a non-capture with two pieces on the board
    basicFEN = "Kn6/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    for m in moves
        if m.to == 8
            make_move!(m,board)
        end
    end
    @assert sum(board.ally_pieces)  == UInt64(1) << 1
    @assert logic.enemy_pieces(board)[1] == UInt64(1) << 8
    @assert length(generate_moves(board)) == 3

    #Test a black move
    basicFEN = "1n6/K7/8/8/8/8/8/8 b KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)
    @assert Whitesmove(board) == false
    @assert length(moves) == 3

    for m in moves
        if m.to == 11
            make_move!(m,board)
        end
    end
    @assert sum(board.enemy_pieces) == UInt64(1) << 11
    GUI = GUIposition(board)
    @assert GUI[12] == 11

    #Test 3 pieces on the board
    basicFEN = "8/8/8/8/8/8/8/NNN5 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)
    @assert length(moves) == 9
    
    for m in moves
        if (m.from == 56) & (m.to == 41)
            make_move!(m,board)
        end
    end
    @assert Whitesmove(board) == false
    @assert sum(board.ally_pieces) == 0

    GUI = GUIposition(board)
    @assert GUI[42] == 5
end
test_makemove()

function test_capture()
    #WKing captures BKnight
    basicFEN = "Kn6/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    @assert sum(board.enemy_pieces) > 0

    for m in moves
        if m.capture_type > 0
            make_move!(m,board)
        end
    end

    @assert sum(board.ally_pieces) == 0
    @assert board.enemy_pieces[1] == UInt64(2)

    @assert length(generate_moves(board)) == 0

    GUI = GUIposition(board)
    @assert GUI[2] == 1
    @assert sum(GUI) == 1
end
test_capture()

function test_attackable()
    basicFEN = "1k7/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)

    attacks = logic.attackable(board,0)
    @assert attacks == UInt(2)

    attacks = logic.attackable(board,1)
    @assert attacks == 0
end
test_attackable()

function test_legal()
    basicFEN = "K7/8/n7/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    checks = logic.attackable(board,0)

    @assert checks == 0
    @assert logic.is_legal(board,UInt8(1),1,checks) == false

    knightFEN = "K7/8/1nnn4/8/N7/8/8/8 w KQkq - 0 1"
    board = Boardstate(knightFEN)

    moves = generate_moves(board)
    @assert length(moves) == 1
    @assert moves[1].capture_type > 0
    @assert moves[1].piece_type == 5

    kingFEN = "Kkk5/8/1nnn4/8/N7/8/8/8 w KQkq - 0 1"
    board = Boardstate(kingFEN)

    moves = generate_moves(board)
    @assert length(moves) == 0
    @assert board.State == Loss()
end
test_legal()

function test_identifyID()
    basicFEN = "1N7/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    ID = logic.identify_piecetype(board.ally_pieces,1)
    @assert ID == 5

    ID = logic.identify_piecetype(board.ally_pieces,2)
    @assert ID == 0
end
test_identifyID()

println("All tests passed")
