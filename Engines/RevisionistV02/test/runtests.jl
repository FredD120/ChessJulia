using RevisionistV02
using logic
using Profile

const benchmark = true
const profil = false

function test_eval()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev == 0 "Start pos should be neutral"

    FEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev >= 100 "Position is worth at least 100 centipawns to white"
end
test_eval()

function test_weighting()
    FEN = "4k3/ppppppp1/8/8/8/8/PPP5/R3K3 w Qkq - 0 1"
    board = Boardstate(FEN)
    num_pcs = count_pieces(board.pieces)

    @assert MGweighting(num_pcs) > EGweighting(num_pcs) "At 13 pieces, weighted towards midgame"

    num_pcs = 10
    @assert MGweighting(num_pcs) < EGweighting(num_pcs) "At 10 pieces, weighted towards endgame"
end
test_weighting()

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
        gameover!(board)
        
        @assert board.State == Loss() "Checkmate in 2 moves"
    end
end
test_mate()

function bench()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    total_t = 0
    eval_t = 0
    movegen_t = 0
    for p in positions[1:50]
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

    #best for 1st 50 positions:
    #1.605 seconds total
    #0.12 seconds evaluation
    #0.287 seconds move gen
else
    println("All cheap tests passed") 
end

#=
testing r1bqk1r1/1p1p1n2/p1n2pN1/2p1b2Q/2P1Pp2/1PN5/PB4PP/R4RK1 w q - 0
Completed. Took 0.019999980926513672 seconds.
Best move = 145589
testing r1n2N1k/2n2K1p/3pp3/5Pp1/b5R1/8/1PPP4/8 w - 0
Completed. Took 0.004999876022338867 seconds.
Best move = 212275
testing r1b1r1k1/1pqn1pbp/p2pp1p1/P7/1n1NPP1Q/2NBBR2/1PP3PP/R6K w - 0
Completed. Took 0.07299995422363281 seconds.
Best move = 24427
testing 5b2/p2k1p2/P3pP1p/n2pP1p1/1p1P2P1/1P1KBN2/7P/8 w - 0
Completed. Took 0.003000020980834961 seconds.
Best move = 25945
testing r3kbnr/1b3ppp/pqn5/1pp1P3/3p4/1BN2N2/PP2QPPP/R1BR2K1 w kq - 0
Completed. Took 0.03400015830993652 seconds.
Best move = 14165
testing r2r2k1/1p1n1pp1/4pnp1/8/PpBRqP2/1Q2B1P1/1P5P/R5K1 b - 0
Completed. Took 0.039999961853027344 seconds.
Best move = 13405
testing 2rq1rk1/pb1n1ppN/4p3/1pb5/3P1Pn1/P1N5/1PQ1B1PP/R1B2RK1 b - 0
Completed. Took 0.016000032424926758 seconds.
Best move = 214740
testing r2qk2r/ppp1bppp/2n5/3p1b2/3P1Bn1/1QN1P3/PP3P1P/R3KBNR w KQkq 0
Completed. Took 0.04399991035461426 seconds.
Best move = 201546
testing rnb1kb1r/p4p2/1qp1pn2/1p2N2p/2p1P1p1/2N3B1/PPQ1BPPP/3RK2R w Kkq 0
Completed. Took 0.03600001335144043 seconds.
Best move = 20340
testing 5rk1/pp1b4/4pqp1/2Ppb2p/1P2p3/4Q2P/P3BPP1/1R3R1K b - 0
Completed. Took 0.04900002479553223 seconds.
Best move = 19114
testing r1b2r1k/ppp2ppp/8/4p3/2BPQ3/P3P1K1/1B3PPP/n3q1NR w - 0
Completed. Took 0.04999995231628418 seconds.
Best move = 211230
testing 1nkr1b1r/5p2/1q2p2p/1ppbP1p1/2pP4/2N3B1/1P1QBPPP/R4RK1 w - 0
Completed. Took 0.05500006675720215 seconds.
Best move = 210206
testing 1nrq1rk1/p4pp1/bp2pn1p/3p4/2PP1B2/P1PB2N1/4QPPP/1R2R1K1 w - 0
Completed. Took 0.029999971389770508 seconds.
Best move = 210710
testing 5k2/1rn2p2/3pb1p1/7p/p3PP2/PnNBK2P/3N2P1/1R6 w - 0
Completed. Took 0.015000104904174805 seconds.
Best move = 213333
testing 8/p2p4/r7/1k6/8/pK5Q/P7/b7 w - 0
Completed. Took 0.0 seconds.
Best move = 31610
testing 1b1rr1k1/pp1q1pp1/8/NP1p1b1p/1B1Pp1n1/PQR1P1P1/4BP1P/5RK1 w - 0
Completed. Took 0.034999847412109375 seconds.
Best move = 23470
testing 1r3rk1/6p1/p1pb1qPp/3p4/4nPR1/2N4Q/PPP4P/2K1BR2 b - 0
Completed. Took 0.03500008583068848 seconds.
Best move = 15018
testing r1b1kb1r/1p1n1p2/p3pP1p/q7/3N3p/2N5/P1PQB1PP/1R3R1K b kq 0
Completed. Took 0.04999995231628418 seconds.
Best move = 15554
testing 3kB3/5K2/7p/3p4/3pn3/4NN2/8/1b4B1 w - 0
Completed. Took 0.0 seconds.
Best move = 15205
testing 1nrrb1k1/1qn1bppp/pp2p3/3pP3/N2P3P/1P1B1NP1/PBR1QPK1/2R5 w - 0
Completed. Took 0.029999971389770508 seconds.
Best move = 26530
testing 3rr1k1/1pq2b1p/2pp2p1/4bp2/pPPN4/4P1PP/P1QR1PB1/1R4K1 b - 0
Completed. Took 0.031000137329101562 seconds.
Best move = 10980
testing r4rk1/p2nbpp1/2p2np1/q7/Np1PPB2/8/PPQ1N1PP/1K1R3R w - 0
Completed. Took 0.031999826431274414 seconds.
Best move = 13573
testing r3r2k/1bq1nppp/p2b4/1pn1p2P/2p1P1QN/2P1N1P1/PPBB1P1R/2KR4 w - 0
Completed. Took 0.006999969482421875 seconds.
Best move = 15165
testing r2q1r1k/3bppbp/pp1p4/2pPn1Bp/P1P1P2P/2N2P2/1P1Q2P1/R3KB1R w KQ 0
Completed. Took 0.009999990463256836 seconds.
Best move = 554945
testing 2kb4/p7/r1p3p1/p1P2pBp/R2P3P/2K3P1/5P2/8 w - 0
Completed. Took 0.0 seconds.
Best move = 132852
testing rqn2rk1/pp2b2p/2n2pp1/1N2p3/5P1N/1PP1B3/4Q1PP/R4RK1 w - 0
Completed. Took 0.08000016212463379 seconds.
Best move = 211246
testing 8/3Pk1p1/1p2P1K1/1P1Bb3/7p/7P/6P1/8 w - 0
Completed. Took 0.004999876022338867 seconds.
Best move = 15025
testing 4rrk1/Rpp3pp/6q1/2PPn3/4p3/2N5/1P2QPPP/5RK1 w - 0
Completed. Took 0.029999971389770508 seconds.
Best move = 201283
testing 2q2rk1/2p2pb1/PpP1p1pp/2n5/5B1P/3Q2P1/4PPN1/2R3K1 w - 0
Completed. Took 0.05500006675720215 seconds.
Best move = 17754
testing rnbq1r1k/4p1bP/p3p3/1pn5/8/2Np1N2/PPQ2PP1/R1B1KB1R w KQ 0
Completed. Took 0.09000015258789062 seconds.
Best move = 26514
testing 4b1k1/1p3p2/4pPp1/p2pP1P1/P2P4/1P1B4/8/2K5 w - 0
Completed. Took 0.0 seconds.
Best move = 13148
testing 8/7p/5P1k/1p5P/5p2/2p1p3/P1P1P1P1/1K3Nb1 w - 0
Completed. Took 0.0 seconds.
Best move = 23990
testing r3kb1r/ppnq2pp/2n5/4pp2/1P1PN3/P4N2/4QPPP/R1B1K2R w KQkq 0
Completed. Took 0.04999995231628418 seconds.
Best move = 21797
testing b4r1k/6bp/3q1ppN/1p2p3/3nP1Q1/3BB2P/1P3PP1/2R3K1 w - 0
Completed. Took 0.019999980926513672 seconds.
Best move = 29651
testing r3k2r/5ppp/3pbb2/qp1Np3/2BnP3/N7/PP1Q1PPP/R3K2R w KQkq 0
Completed. Took 0.02500009536743164 seconds.
Best move = 142045
testing r1k1n2n/8/pP6/5R2/8/1b1B4/4N3/1K5N w - 0
Completed. Took 0.004999876022338867 seconds.
Best move = 2795
testing 1k6/bPN2pp1/Pp2p3/p1p5/2pn4/3P4/PPR5/1K6 w - 0
Completed. Took 0.002000093460083008 seconds.
Best move = 27539
testing 8/6N1/3kNKp1/3p4/4P3/p7/P6b/8 w - 0
Completed. Took 0.003000020980834961 seconds.
Best move = 6825
testing r1b1k2r/pp3ppp/1qn1p3/2bn4/8/6P1/PPN1PPBP/RNBQ1RK1 w kq 0
Completed. Took 0.029999971389770508 seconds.
Best move = 178100
testing r3kb1r/3n1ppp/p3p3/1p1pP2P/P3PBP1/4P3/1q2B3/R2Q1K1R b kq 0
Completed. Took 0.06400012969970703 seconds.
Best move = 525825
testing 3q1rk1/2nbppb1/pr1p1n1p/2pP1Pp1/2P1P2Q/2N2N2/1P2B1PP/R1B2RK1 w - 0
Completed. Took 0.09599995613098145 seconds.
Best move = 31034
testing 8/2k5/N3p1p1/2KpP1P1/b2P4/8/8/8 b - 0
Completed. Took 0.0 seconds.
Best move = 5713
testing 2r1rbk1/1pqb1p1p/p2p1np1/P4p2/3NP1P1/2NP1R1Q/1P5P/R5BK w - 0
Completed. Took 0.04499983787536621 seconds.
Best move = 14165
testing rnb2rk1/pp2q2p/3p4/2pP2p1/2P1Pp2/2N5/PP1QBRPP/R5K1 w - 0
Completed. Took 0.04500007629394531 seconds.
Best move = 22436
testing 5rk1/p1p1rpb1/q1Pp2p1/3Pp2p/4Pn2/1R4N1/P1BQ1PPP/R5K1 w - 0
Completed. Took 0.09500002861022949 seconds.
Best move = 22859
testing 8/4nk2/1p3p2/1r1p2pp/1P1R1N1P/6P1/3KPP2/8 w - 0
Completed. Took 0.009999990463256836 seconds.
Best move = 212781
testing 4kbr1/1b1nqp2/2p1p3/2N4p/1p1PP1pP/1PpQ2B1/4BPP1/r4RK1 w - 0
Completed. Took 0.015000104904174805 seconds.
Best move = 127467
testing r1b2rk1/p2nqppp/1ppbpn2/3p4/2P5/1PN1PN2/PBQPBPPP/R4RK1 w - 0
Completed. Took 0.059999942779541016 seconds.
Best move = 16725
testing r1b1kq1r/1p1n2bp/p2p2p1/3PppB1/Q1P1N3/8/PP2BPPP/R4RK1 w kq 0
Completed. Took 0.02499985694885254 seconds.
Best move = 21797
testing r4r1k/p1p3bp/2pp2p1/4nb2/N1P4q/1P5P/PBNQ1PP1/R4RK1 b - 0
Completed. Took 0.05500006675720215 seconds.
Best move = 22252
Took 1.6050000190734863 seconds. 0.12099933624267578 s evaluating positions, 0.2870016098022461 s generating moves.
=#