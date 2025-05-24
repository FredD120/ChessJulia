using RevisionistV02
using logic

function test_eval()
    FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    println(ev)
    @assert ev == 0 "Start pos should be neutral"

    FEN = "8/P6k/K7/8/8/8/8/8 w - - 0 1"
    board = Boardstate(FEN)
    ev = evaluate(board)

    @assert ev >= eval(val(Pawn())) "Position is worth at least 100 centipawns to white"
end
test_eval()

function test_best()
    FEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)
    best = best_move(board,moves)
    ind = findfirst(i->i.capture_type==val(Queen()),moves)

    @assert best == moves[ind] "Bishop should capture queen as black"

    FEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)
    best = best_move(board,moves)
    ind = findfirst(i->i.capture_type==val(Queen()),moves)

    @assert best == moves[ind] "Bishop should capture queen as white"

    FEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)
    best = best_move(board,moves)
    ind = findfirst(i->i.to==62,moves)

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

println("All tests passed")