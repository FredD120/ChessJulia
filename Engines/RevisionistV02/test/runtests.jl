using RevisionistV02
using logic

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
end
test_best()

println("All tests passed")