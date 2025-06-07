using RevisionistV03_02
using logic
using Profile

const profil = true
const MAXTIME = 0.05

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

function test_ordering()
    FEN = "K7/R7/R7/8/8/8/8/7k w - - 0 1"
    board = Boardstate(FEN)
    moves = generate_moves(board)

    best_move = moves[10]
    scores = score_moves(moves,best_move,true)
    moves = sort_moves(moves,scores)

    @assert moves[1] == best_move "Current best move should be played first"
end
test_ordering()

function test_best()
    FEN = "K6Q/8/8/8/8/8/8/b6k b - - 0 1"
    board = Boardstate(FEN)
    best,log = best_move(board,MAXTIME)

    moves = generate_moves(board)
    ind = findfirst(i->cap_type(i)==val(Queen()),moves)
    @assert best == moves[ind] "Bishop should capture queen as black"

    FEN = "k6q/8/8/8/8/8/8/B6K w - - 0 1"
    board = Boardstate(FEN)
    best,log = best_move(board,MAXTIME)

    moves = generate_moves(board)
    ind = findfirst(i->cap_type(i)==val(Queen()),moves)
    @assert best == moves[ind] "Bishop should capture queen as white"

    FEN = "k7/8/8/8/8/8/5K2/7q b - - 0 1"
    board = Boardstate(FEN)
    best,log = best_move(board,MAXTIME)

    moves = generate_moves(board)
    ind = findfirst(i->to(i)==62,moves)
    @assert best != moves[ind] "Queen should not allow itself to be captured"
end
test_best()

function test_mate()
    #mate in 2
    for FEN in ["K7/R7/R7/8/8/8/8/7k w - - 0 1","k7/r7/r7/8/8/8/8/7K b - - 0 1"]
        board = Boardstate(FEN)
        best,log = best_move(board,MAXTIME)
        #rook moves to cut off king
        make_move!(best,board)
        moves = generate_moves(board)
        #king response doesn't matter
        make_move!(moves[1],board)
        best,log = best_move(board,MAXTIME)
        make_move!(best,board)
        gameover!(board)
        
        @assert board.State == Loss() "Checkmate in 2 moves"
    end
end
test_mate()

function profile()
    positions = readlines("$(dirname(@__DIR__))/test/test_positions.txt")

    #slow position
    FEN = split(split(positions[12],";")[1],"- bm")[1]*"0"
    board = Boardstate(FEN)

    best,log = best_move(board,MAXTIME)

    @profile best_move(board,MAXTIME*10)
    Profile.print()
end
if profil 
    profile()
end

println("All tests passed")

