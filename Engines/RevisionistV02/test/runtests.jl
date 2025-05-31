using RevisionistV02
using logic
using Profile

const benchmark = true
const profil = false

function test_index()
    pos = 17
    @assert rank(pos) == 5
    @assert file(pos) == 1

    bpos = side_index(Black(),pos)
    @assert rank(bpos) == 2 "Mirrored about the x axis"
    @assert file(bpos) == 1
end
test_index()

function test_eval()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev == 0 "Start pos should be neutral"

    FEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev >= eval(val(Pawn())) "Position is worth at least 100 centipawns to white"
end
test_eval()

function test_positional()
    FEN = "1n2k1n1/8/8/8/8/8/8/4K3 b KQkq - 0 1"
    board = Boardstate(FEN)
    ev1 = -evaluate(board)

    FEN = "4k3/8/8/3n4/8/4n3/8/4K3 b KQkq - 0 1"
    board = Boardstate(FEN)
    ev2 = -evaluate(board)

    @assert ev2 > ev1 "Knights encouraged to be central"

    FEN = "4k3/pppppppp/8/8/PP4PP/8/2PPPP2/4K3 w KQkq - 0 1"
    board = Boardstate(FEN)
    ev1 = evaluate(board)

    FEN = "4k3/pppppppp/8/8/2PPPP2/8/PP4PP/4K3 w KQkq - 0 1"
    board = Boardstate(FEN)
    ev2 = evaluate(board)

    @assert ev2 > ev1 "Push central pawns first"

    FEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/R3K3 w Qkq - 0 1"
    board = Boardstate(FEN)
    ev1 = evaluate(board)

    FEN = "4k3/pppppppp/8/8/8/8/PPPPPPPP/2KR4 w KQkq - 0 1"
    board = Boardstate(FEN)
    ev2 = evaluate(board)

    @assert ev2 > ev1 "Castling is positionally favourable"
end
test_positional()

function test_weighting()
    FEN = "4k3/ppppppp1/8/8/8/8/PPP5/R3K3 w Qkq - 0 1"
    board = Boardstate(FEN)
    num_pcs = count_pieces(board.pieces)

    @assert MGweighting(num_pcs) > EGweighting(num_pcs) "At 13 pieces, weighted towards midgame"

    num_pcs = 10
    @assert MGweighting(num_pcs) < EGweighting(num_pcs) "At 10 pieces, weighted towards endgame"
end
test_weighting()

function test_best()
    FEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)
    best = best_move(board,moves)
    ind = findfirst(i->cap_type(i)==val(Queen()),moves)

    @assert best == moves[ind] "Bishop should capture queen as black"

    FEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)
    best = best_move(board,moves)
    ind = findfirst(i->cap_type(i)==val(Queen()),moves)

    @assert best == moves[ind] "Bishop should capture queen as white"

    FEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)
    best = best_move(board,moves)
    ind = findfirst(i->to(i)==62,moves)

    @assert best != moves[ind] "Queen should not allow itself to be captured"
end
test_best()

function test_mate()
    #mate in 2
    for FEN in ["K7/R7/R7/8/8/8/8/7k w - - 0 1","k7/r7/r7/8/8/8/8/7K b - - 0 1"]
        board = Boardstate(FEN)
        moves = generate_moves(board)
        best = best_move(board,moves)
        #rook moves to cut off king
        make_move!(best,board)
        moves = generate_moves(board)
        #king response doesn't matter
        make_move!(moves[1],board)
        moves = generate_moves(board)
        best = best_move(board,moves)
        make_move!(best,board)
        moves = generate_moves(board)
        
        @assert board.State == Loss() "Checkmate in 2 moves"
    end
end
test_mate()

function bench()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    total_t = 0
    eval_t = 0
    movegen_t = 0
    for p in positions[1:15]
        FEN = split(split(p,";")[1],"- bm")[1]*"0"
        println("testing $FEN")
        board = Boardstate(FEN)
        t = time()
        best,log = best_move(board)
        total_t += time() - t
        println("Completed. Took $(time() - t) seconds.")
        println("Best move = $(best)")
        eval_t += log.evaltime
        movegen_t += log.movegentime    
    end

    println("Took $total_t seconds. $eval_t s evaluating positions, $movegen_t s generating moves.")
end

function profile()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    #slow position
    FEN = split(split(positions[12],";")[1],"- bm")[1]*"0"
    board = Boardstate(FEN)

    best,log = best_move(board)

    @profile best_move(board)
    Profile.print()
end
if profil 
    profile()
end

if benchmark
    bench()
    println("All tests passed")

    #best for 1st 15 positions:
    #33.4 seconds total
    #23.8 seconds evaluation
    #9.0 seconds move gen
else
    println("All cheap tests passed") 
end

#=
testing r1bqk1r1/1p1p1n2/p1n2pN1/2p1b2Q/2P1Pp2/1PN5/PB4PP/R4RK1 w q - 0
Completed. Took 1.6529998779296875 seconds.
Best move = 145589
testing r1n2N1k/2n2K1p/3pp3/5Pp1/b5R1/8/1PPP4/8 w - 0
Completed. Took 0.13700008392333984 seconds.
Best move = 212275
testing r1b1r1k1/1pqn1pbp/p2pp1p1/P7/1n1NPP1Q/2NBBR2/1PP3PP/R6K w - 0
Completed. Took 3.3420000076293945 seconds.
Best move = 24427
testing 5b2/p2k1p2/P3pP1p/n2pP1p1/1p1P2P1/1P1KBN2/7P/8 w - 0
Completed. Took 0.07899999618530273 seconds.
Best move = 25945
testing r3kbnr/1b3ppp/pqn5/1pp1P3/3p4/1BN2N2/PP2QPPP/R1BR2K1 w kq - 0
Completed. Took 5.5929999351501465 seconds.
Best move = 14165
testing r2r2k1/1p1n1pp1/4pnp1/8/PpBRqP2/1Q2B1P1/1P5P/R5K1 b - 0
Completed. Took 1.6000001430511475 seconds.
Best move = 13405
testing 2rq1rk1/pb1n1ppN/4p3/1pb5/3P1Pn1/P1N5/1PQ1B1PP/R1B2RK1 b - 0
Completed. Took 2.5299999713897705 seconds.
Best move = 214740
testing r2qk2r/ppp1bppp/2n5/3p1b2/3P1Bn1/1QN1P3/PP3P1P/R3KBNR w KQkq 0
Completed. Took 0.9960000514984131 seconds.
Best move = 201546
testing rnb1kb1r/p4p2/1qp1pn2/1p2N2p/2p1P1p1/2N3B1/PPQ1BPPP/3RK2R w Kkq 0
Completed. Took 1.4300000667572021 seconds.
Best move = 20340
testing 5rk1/pp1b4/4pqp1/2Ppb2p/1P2p3/4Q2P/P3BPP1/1R3R1K b - 0
Completed. Took 1.2760000228881836 seconds.
Best move = 19172
testing r1b2r1k/ppp2ppp/8/4p3/2BPQ3/P3P1K1/1B3PPP/n3q1NR w - 0
Completed. Took 1.6079998016357422 seconds.
Best move = 211230
testing 1nkr1b1r/5p2/1q2p2p/1ppbP1p1/2pP4/2N3B1/1P1QBPPP/R4RK1 w - 0
Completed. Took 6.9100000858306885 seconds.
Best move = 210206
testing 1nrq1rk1/p4pp1/bp2pn1p/3p4/2PP1B2/P1PB2N1/4QPPP/1R2R1K1 w - 0
Completed. Took 3.884999990463257 seconds.
Best move = 210710
testing 5k2/1rn2p2/3pb1p1/7p/p3PP2/PnNBK2P/3N2P1/1R6 w - 0
Completed. Took 1.2049999237060547 seconds.
Best move = 213333
testing 8/p2p4/r7/1k6/8/pK5Q/P7/b7 w - 0
Completed. Took 0.08800005912780762 seconds.
Best move = 31610
Took 32.33200001716614 seconds. 23.1629958152771 s evaluating positions, 8.633004665374756 s generating moves.
All tests passed
=#