using logic
using BenchmarkTools

const expensive = false

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
    @assert Whitesmove(board.ColourIndex) == true
    @assert board.Data.EnPassant[end] == UInt64(0)
    @assert logic.ally_pieces(board)[3] != UInt64(0)
    @assert logic.enemy_pieces(board)[3] != UInt64(0)
    @assert logic.enemy_pieces(board)[1] == UInt64(1) << 4
    @assert logic.ally_pieces(board)[1] == UInt64(1) << 60
    @assert board.Data.Halfmoves[end] == 0
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

function test_BitboardUnion()
    board = Boardstate(FEN)
    white = logic.BitboardUnion(logic.ally_pieces(board))
    black = logic.BitboardUnion(logic.enemy_pieces(board))
    all = logic.BitboardUnion(board.pieces)
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
test_BitboardUnion()

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
    pieces::Vector{UInt64}
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

function test_Zobrist()
    board = Boardstate(FEN)
    @assert board.ZHash == 3988342487599293876

    moves = generate_moves(board)
    for move in moves
       if (move.from == 57) & (move.to == 40)
        make_move!(move,board)
       end
    end
    @assert board.Data.ZHashHist[1] == 3988342487599293876

    newFEN = "rnbqkbnr/pppppppp/8/8/8/N7/PPPPPPPP/R1BQKBNR b KQkq - 1 1"
    newboard = Boardstate(newFEN)
    @assert board.ZHash == newboard.ZHash
end
test_Zobrist()

function test_movfromloc()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    legal_info = logic.LegalInfo(0,0,0,0)
    moves = logic.moves_from_location(UInt8(1),board,UInt64(3),2,UInt64(0),legal_info,false)
    @assert length(moves) == 2
    @assert moves[1].capture_type == 0
    @assert moves[2].from == 2
    @assert moves[1].piece_type == 1
end
test_movfromloc()

function test_kingmoves()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    legal_info = logic.LegalInfo(0,0,0,0)
    moves = logic.get_kingmoves(UInt8(0),board,UInt64(0),UInt64(0),legal_info)
    @assert length(moves) == 3
end
test_kingmoves()

function test_knightmoves()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    legal_info = logic.LegalInfo(0,0,0,0)
    moves = logic.get_knightmoves(UInt8(0),board,UInt64(0),UInt64(0),legal_info)
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
    board.Data.Halfmoves[end] = 100
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

    @assert Whitesmove(board.ColourIndex) == false
    @assert board.Data.Halfmoves[end] == UInt8(1)
    @assert logic.enemy_pieces(board)[1] == UInt64(2)

    #Test making a non-capture with three pieces on the board
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    for m in moves
        if m.to == 8
            make_move!(m,board)
        end
    end
    @assert sum(logic.ally_pieces(board)[2:end])  == UInt64(1) << 1
    @assert logic.enemy_pieces(board)[1] == UInt64(1) << 8
    @assert length(generate_moves(board)) == 6

    #Test a black move
    basicFEN = "1n6/K7/8/8/8/8/8/7k b KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)
    @assert Whitesmove(board.ColourIndex) == false
    @assert length(moves) == 6

    for m in moves
        if m.to == 11
            make_move!(m,board)
        end
    end
    @assert sum(logic.enemy_pieces(board)[2:end]) == 1<<11
    GUI = GUIposition(board)
    @assert GUI[12] == 11

    #Test 3 pieces on the board
    basicFEN = "k7/8/8/8/8/8/8/NNN4K w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)
    @assert length(moves) == 12
    
    for m in moves
        if (m.from == 56) & (m.to == 41)
            make_move!(m,board)
        end
    end
    @assert Whitesmove(board.ColourIndex) == false
    @assert sum(logic.ally_pieces(board)[2:end]) == 0

    GUI = GUIposition(board)
    @assert GUI[42] == 5
end
test_makemove()

function test_capture()
    #WKing captures BKnight
    basicFEN = "Kn6/8/8/8/8/8/8/7k w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    @assert sum(logic.enemy_pieces(board)) > 0

    for m in moves
        if m.capture_type > 0
            make_move!(m,board)
        end
    end

    @assert sum(logic.ally_pieces(board)[2:end]) == 0
    @assert logic.enemy_pieces(board)[1] == UInt64(2)

    @assert length(generate_moves(board)) == 3

    GUI = GUIposition(board)
    @assert GUI[2] == 1
    @assert sum(GUI) == 8
end
test_capture()

function test_attack_pcs()
    basicFEN = "1k7/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)

    attacks = logic.attack_pcs(board,UInt64(0),0)
    @assert attacks == UInt(2)

    attacks = logic.attack_pcs(board,UInt64(0),1)
    @assert attacks == 0
end
test_attack_pcs()

function test_legal()
    basicFEN = "K7/8/n7/8/8/8/8/8 w - 0 1"
    board = Boardstate(basicFEN)
    legal_info = logic.attack_info(board,UInt64(0),0)

    @assert legal_info.checks == 0
    @assert logic.is_legal(board,UInt8(1),1,UInt64(0),legal_info) == false

    knightFEN = "K7/8/1nnn4/8/N7/8/8/8 w - 0 1"
    board = Boardstate(knightFEN)

    moves = generate_moves(board)
    @assert length(moves) == 1
    @assert moves[1].capture_type > 0
    @assert moves[1].piece_type == 5

    kingFEN = "Kkk5/8/1nnn4/8/N7/8/8/8 w - 0 1"
    board = Boardstate(kingFEN)

    moves = generate_moves(board)
    @assert length(moves) == 0
    @assert board.State == Loss()

    "WKing stalemated in corner"
    slidingFEN = "K7/7r/8/8/8/8/8/1r4k1 w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 0
    @assert board.State == Draw()

    "WKing checkmated by queen and 2 rooks, unless bishop blocks"
    slidingFEN = "1R4B1/RK6/7r/8/8/8/8/r1r3kq w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 1
    @assert board.State == Neutral()
end
test_legal()

function test_identifyID()
    basicFEN = "1N7/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(basicFEN)
    ID = logic.identify_piecetype(logic.ally_pieces(board),1)
    @assert ID == 5

    ID = logic.identify_piecetype(logic.ally_pieces(board),2)
    @assert ID == 0
end
test_identifyID()

function test_unmake()
    #WKing captures BKnight then unmake
    basicFEN = "Kn6/8/8/8/8/8/8/7k w KQkq - 0 1"
    board = Boardstate(basicFEN)
    moves = generate_moves(board)

    for m in moves
        if m.capture_type > 0
            make_move!(m,board)
        end
    end
    unmake_move!(board)

    @assert Whitesmove(board.ColourIndex) == true
    @assert logic.ally_pieces(board)[1] == UInt64(1)
    @assert logic.enemy_pieces(board)[5] == UInt64(2)

    moves = generate_moves(board)
    for m in moves
        if m.to == 8
            make_move!(m,board)
        end
    end
    @assert logic.enemy_pieces(board)[1] == UInt(1) << 8
    moves = generate_moves(board)
    for m in moves
        if m.to == 16
            make_move!(m,board)
        end
    end
    @assert logic.enemy_pieces(board)[5] == UInt(1) << 16
    moves = generate_moves(board)
    for m in moves
        if m.capture_type == 5
            make_move!(m,board)
        end
    end
    @assert logic.ally_pieces(board)[5] == 0
    @assert length(board.Data.Halfmoves) == 2
    unmake_move!(board)
    unmake_move!(board)
    unmake_move!(board)

    @assert Whitesmove(board.ColourIndex) == true
    @assert logic.ally_pieces(board)[1] == UInt64(1)
    @assert logic.enemy_pieces(board)[5] == UInt64(2)
    @assert length(board.Data.Halfmoves) == 1
end
test_unmake()

function test_repetition()
    basicFEN = "K7/8/8/8/8/8/8/7k w KQkq - 0 1"
    board = Boardstate(basicFEN)

    for i in 1:8
        moves = generate_moves(board)
        for m in moves
            pos = -1
            if i%2==1
                pos = 0
            else
                pos = 63
            end

            if (m.from == pos) | (m.to == pos)
                make_move!(m,board)
                break
            end
        end
    end
    #need to generate moves to figure out if it is a draw
    generate_moves(board)
    @assert board.State == Draw()
end
test_repetition()

function test_UCI()
    str1 = logic.UCIpos(0)
    str2 = logic.UCIpos(63)
    @assert (str1 == "a8") & (str2 == "h1")

    move = Move(1,2,54,0)
    mvstr = UCImove(move)
    @assert mvstr == "c8g2"
end
test_UCI()

"check all sliding attacks and quiets are generated correctly, not including checks"
function test_sliding()
    slidingFEN = "Q6r/8/2K5/8/8/8/8/b2k3 w - 0 1"
    board = Boardstate(slidingFEN)

    moves = generate_moves(board)
    @assert length(moves) == 23
    @assert count(i->(i.capture_type > 0),moves) == 2

    for m in moves
        if m.capture_type == logic.Rook
            make_move!(m,board)
        end
    end
    newmoves = generate_moves(board)
    @assert length(newmoves) == 12
    @assert count(i->(i.capture_type == logic.Queen),newmoves) == 1
end
test_sliding()

function test_perft()
    basicFEN = "K7/8/8/8/8/8/8/7k w KQkq - 0 1"
    board = Boardstate(basicFEN)

    leaves = perft(board,2)
    @assert leaves == 9
end
test_perft()

function test_speed()
    FEN = "nnnnknnn/8/8/8/8/8/8/NNNNKNNN w - 0 1"
    board = Boardstate(FEN)

    t = time()
    leaves = perft(board,5)
    @assert leaves == 11813050
    Δt = time() - t
    return leaves,Δt
end

function benchmarkspeed(leafcount)
    FEN = "nnnnknnn/8/8/8/8/8/8/NNNNKNNN w - 0 1"
    board = Boardstate(FEN)
    depth = 5

    trial = @benchmark perft($board,$depth)
    minimum_time = minimum(trial).time * 1e-9

    println("Benchmarked nps = $(leafcount/minimum_time)")
end

if expensive
    leaves,Δt = test_speed()
    println("Leaves: $leaves. NPS = $(leaves/Δt) nodes/second")

    #benchmarkspeed(leaves)
    #best = 1.235e7
end

println("All tests passed")
