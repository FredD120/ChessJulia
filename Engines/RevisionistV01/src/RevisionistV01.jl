module RevisionistV01

#=
Plays totally random moves
=#

using logic
using Random
rng = Xoshiro(2000)

export best_move

"Evaluates the position to return the best move"
function best_move(board::Boardstate,moves::Vector{UInt32})
    return rand(rng,moves)
end

"Wrapper for passing board to best move"
function best_move(position::Boardstate)
    moves = generate_moves(position)
    return best_move(position,moves)
end

end #module