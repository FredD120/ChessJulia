using logic
using BenchmarkTools

const expensive = true
const verbose = true

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
    white = logic.BBunion(logic.ally_pieces(board))
    black = logic.BBunion(logic.enemy_pieces(board))
    all = logic.BBunion(board.pieces)
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

function test_movfromloc()
    simpleFEN = "8/8/8/8/8/8/8/8 w KQkq - 0 1"
    board = Boardstate(simpleFEN)
    moves = logic.moves_from_location(logic.val(King()),logic.enemy_pieces(board),UInt64(3),2,false)
    @assert length(moves) == 2
    @assert moves[1].capture_type == 0
    @assert moves[2].from == 2
    @assert moves[1].piece_type == 1
end
test_movfromloc()

function test_legalinfo()
    simpleFEN = "K7/R7/8/8/8/8/8/r6q w - - 0 1"
    board = Boardstate(simpleFEN)    
    all_pcs = logic.BBunion(board.pieces)
    info = logic.attack_info(logic.enemy_pieces(board),all_pcs,0,1)

    @assert info.checks == (UInt64(1)<<63) "only bishop attacks king"
    @assert info.attack_num == 1
    @assert length(logic.identify_locations(info.blocks)) == 6 "6 squares blocking bishop"

    simpleFEN = "K7/7R/8/8/8/8/8/qq6 w - - 0 1"
    board = Boardstate(simpleFEN)    
    all_pcs = logic.BBunion(board.pieces)
    info = logic.attack_info(logic.enemy_pieces(board),all_pcs,0,1)
    @assert length(logic.identify_locations(info.blocks)) == 6 "6 squares blocking queen attack"

    simpleFEN = "4k3/8/8/8/4q3/8/4B3/1Q2K3 w - 0 1"
    board = Boardstate(simpleFEN)  
    all_pcs = logic.BBunion(board.pieces)
    kingBB = logic.ally_pieces(board)[val(King())]
    kingpos = logic.identify_locations(kingBB)[1]
    info = logic.attack_info(logic.enemy_pieces(board),all_pcs,kingpos,kingBB)

    @assert info.blocks == typemax(UInt64)
    @assert info.checks == typemax(UInt64)
end
test_legalinfo()

function testpins()
    simpleFEN = "K7/R7/8/8/8/8/8/r6b w - - 0 1"
    board = Boardstate(simpleFEN)    
    all_pcs = logic.BBunion(board.pieces)
    ally_pcs = logic.BBunion(logic.ally_pieces(board))
    enemy = logic.enemy_pieces(board)

    rookpins,bishoppins = logic.detect_pins(0,enemy,all_pcs,ally_pcs)

    @assert length(logic.identify_locations(rookpins)) == 7
    @assert bishoppins == 0

    simpleFEN = "4k3/8/8/8/4b3/8/4B3/1Q2K3 w - 0 1"
    board = Boardstate(simpleFEN)    
    all_pcs = logic.BBunion(board.pieces)
    ally_pcs = logic.BBunion(logic.ally_pieces(board))
    enemy = logic.enemy_pieces(board)
    kingBB = logic.ally_pieces(board)[val(King())]
    kingpos = logic.identify_locations(kingBB)[1]

    rookpins,bishoppins = logic.detect_pins(kingpos,enemy,all_pcs,ally_pcs)
    @assert rookpins == 0
    @assert bishoppins == 0
end
testpins()

function test_castle()
    cFEN = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
    board = Boardstate(cFEN)
    moves = generate_moves(board)

    Kcount = 0
    Qcount = 0
    for m in moves 
        if m.flag == KCASTLE
            Kcount +=1
        elseif m.flag == QCASTLE
            Qcount +=1
        elseif (m.from == 63) & (m.capture_type == val(Rook()))
            make_move!(m,board)
        end
    end
    @assert Kcount == 1 "Should be able to castle kingside"
    @assert Qcount == 1 "Should be able to castle queenside"
    @assert board.Castle == Int(0b1010) "Both sides have lost kingside castling"

    bmoves = generate_moves(board)
    Kcount = 0
    Qcount = 0
    for m in bmoves 
        if m.flag == KCASTLE
            Kcount +=1
        elseif m.flag == QCASTLE
            Qcount +=1
        elseif m.to == 12
            make_move!(m,board)
        end
    end
    @assert Kcount + Qcount == 0 "Should not be able to castle"

    moves = generate_moves(board)
    Kcount = 0
    Qcount = 0
    for m in moves 
        if m.flag == KCASTLE
            Kcount +=1
        elseif m.flag == QCASTLE
            Qcount +=1
        end
    end
    @assert Kcount == 0 "Should not be able to castle kingside"
    @assert Qcount == 1 "Should be able to castle queenside"
    @assert length(board.Data.Castling) == 3

    cFEN = "r3k2r/8/8/8/8/8/8/RB2K2R w KQkq - 0 1"
    board = Boardstate(cFEN)
    moves = generate_moves(board)
    @assert all(i -> (i.flag != QCASTLE), moves) "cannot castle queenside when piece in the way"
end
test_castle()

function test_attckpcs()
    simpleFEN = "K6r/2n5/8/8/8/8/8/7b w - - 0 1"
    board = Boardstate(simpleFEN)    
    all_pcs = logic.BBunion(board.pieces)

    checkers = logic.attack_pcs(logic.enemy_pieces(board),all_pcs,0)
    @assert checkers == (UInt64(1)<<7)|(UInt64(1)<<10)|(UInt64(1)<<63) "2 sliding piece attacks and a knight"
end
test_attckpcs()

function test_allposs()
    simpleFEN = "R1R1R1R1/8/8/8/8/8/8/1R1R1R1R b - - 0 1"
    board = Boardstate(simpleFEN) 
    all_pcs = logic.BBunion(board.pieces)  
    attkBB = logic.all_poss_moves(logic.enemy_pieces(board),all_pcs)

    @assert attkBB == typemax(UInt64) "rooks are covering all squares"
end
test_allposs()

function test_movegetters()
    simpleFEN = "8/8/4nK2/8/8/8/8/8 w - - 0 1"
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

    simpleFEN = "8/8/4nK2/8/8/8/8/8 w - - 0 1"
    board = Boardstate(simpleFEN)
    board.Data.Halfmoves[end] = 100
    moves = generate_moves(board)
    @assert length(moves) == 0
    @assert board.State == Draw()
end
test_movegetters()

function test_makemove()
    #Test making a move with only one piece on the board
    basicFEN = "K7/8/8/8/8/8/8/8 w - - 0 1"
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
    basicFEN = "1n6/K7/8/8/8/8/8/7k b - - 0 1"
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
    basicFEN = "k7/8/8/8/8/8/8/NNN4K w - - 0 1"
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
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
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

function test_legal()
    knightFEN = "K7/8/1nnn4/8/N7/8/8/8 w - 0 1"
    board = Boardstate(knightFEN)

    moves = generate_moves(board)
    @assert length(moves) == 1 "Wknight must capture knight"
    @assert moves[1].capture_type > 0
    @assert moves[1].piece_type == val(Knight())

    #WKing stalemated in corner
    slidingFEN = "K7/7r/8/8/8/8/8/1r4k1 w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 0 "White king not stalemated"
    @assert board.State == Draw()

    #WKing checkmated by queen and 2 rooks, unless bishop blocks
    slidingFEN = "1R4B1/RK6/7r/8/8/8/8/r1r3kq w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 1 "King moves backwards into check?"
    @assert board.State == Neutral()
    @assert moves[1].piece_type == val(Bishop())

    #Wking is checkmated as bishop cannot capture rook because pinned by queen
    slidingFEN = "K5Nr/8/8/3B4/8/8/r7/1r5q w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 0 "White bishop cannot block"
    @assert board.State == Loss()

    #Only legal move is to block with rook
    slidingFEN = "K5Nr/8/8/3B4/7R/8/q7/1r5q w - 0 1"
    board = Boardstate(slidingFEN)
    moves = generate_moves(board)
    @assert length(moves) == 1 "White rook must block"
end
test_legal()

function test_identifyID()
    basicFEN = "1N7/8/8/8/8/8/8/8 w - - 0 1"
    board = Boardstate(basicFEN)
    ID = logic.identify_piecetype(logic.ally_pieces(board),1)
    @assert ID == 5

    ID = logic.identify_piecetype(logic.ally_pieces(board),2)
    @assert ID == 0
end
test_identifyID()

function test_unmake()
    #WKing captures BKnight then unmake
    basicFEN = "Kn6/8/8/8/8/8/8/7k w - - 0 1"
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
    basicFEN = "K7/8/8/8/8/8/8/7k w - - 0 1"
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

    move = Move(1,2,54,0,0)
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
        if m.capture_type == val(Rook())
            make_move!(m,board)
        end
    end
    newmoves = generate_moves(board)
    @assert length(newmoves) == 12
    @assert count(i->(i.capture_type == val(Queen())),newmoves) == 1
end
test_sliding()

function test_Zobrist()
    board = Boardstate(FEN)
    moves = generate_moves(board)
    for move in moves
       if (move.from == 57) & (move.to == 40)
        make_move!(move,board)
       end
    end

    newFEN = "rnbqkbnr/pppppppp/8/8/8/N7/PPPPPPPP/R1BQKBNR b KQkq - 1 1"
    newboard = Boardstate(newFEN)
    @assert board.ZHash == newboard.ZHash

    #should end up back at start position
    moves = generate_moves(board)
    for move in moves
       if (move.from == 1) & (move.to == 16)
        make_move!(move,board)
       end
    end
    moves = generate_moves(board)
    for move in moves
       if (move.from == 40) & (move.to == 57)
        make_move!(move,board)
       end
    end
    moves = generate_moves(board)
    for move in moves
       if (move.from == 16) & (move.to == 1)
        make_move!(move,board)
       end
    end
    @assert board.ZHash == board.Data.ZHashHist[1] "Zhash should be identical to start pos"

    unmake_move!(board)
    unmake_move!(board)
    unmake_move!(board)
    @assert board.ZHash == newboard.ZHash "should be able to recover Zhash after unmaking move"
end
test_Zobrist()

function test_perft()
    basicFEN = "K7/8/8/8/8/8/8/7k w - - 0 1"
    board = Boardstate(basicFEN)

    leaves = perft(board,2)
    @assert leaves == 9
end
test_perft()

function test_speed()
    FENs = ["nnnnknnn/8/8/8/8/8/8/NNNNKNNN w - 0 1",
    "bbbqknbq/8/8/8/8/8/8/QNNNKBBQ w - 0 1",
    "r3k2r/4q1b1/bn3n2/4N3/8/2N2Q2/3BB3/R3K2R w KQkq -"]
    Depths = [5,4,4]
    Targets = [11813050,7466475,7960855]
    Δt = 0
    leaves = 0

    for (FEN,depth,target) in zip(FENs,Depths,Targets)
        board = Boardstate(FEN)
        if verbose
            println("Testing position: $FEN")
        end
        t = time()
        cur_leaves = perft(board,depth,verbose)
        Δt += time() - t
        leaves += cur_leaves

        if target == 0
            println(cur_leaves)
        else
            @assert cur_leaves == target "failed on FEN $FEN, missing $(target-cur_leaves) nodes"
        end
    end
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
