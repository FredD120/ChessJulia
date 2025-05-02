using JLD2

msb(b::UInt64) = 63 - leading_zeros(b)
lsb(b::UInt64) = trailing_zeros(b)

#define constants
const MAX_SQUARES = 12 #maximum bits in a mask for a single square piece

const BB_RANKS = [UInt64(0xff) << (8 * (7-i)) for i in 0:7]
const BB_FILES = [UInt64(0x101010101010101) << i for i in 0:7]

square_rank(sq) = 7 - (sq >> 3)
square_file(sq) = sq & 7

square_distance(a, b) = max(abs(square_rank(a) - square_rank(b)),abs(square_file(a) - square_file(b)))

struct Reference
    occupied::UInt64
    attack::UInt64
end

mutable struct StackFrame
    mask::UInt64          # The occupancy mask for this level (includes bits up to this level)
    bits::Int             # Number of relevant bits in the mask (64 - trailing_zeros(mask))
    prefix_bits::Int      # Number of bits covered by the previous level's mask
    is_last::Bool         # Is this the final level?

    # Range and step for magic number candidates at this level
    min_magic::UInt64
    step_magic::UInt64
    max_magic::UInt64

    refs::Vector{Reference} # Pre-calculated (occupied, attack) pairs for this mask
    stats::Int              # Count of magic candidates tested at this level

    # Collision detection array (size 2^SHIFT).
    # Stores the magic number that last wrote to this index.
    age::Vector{UInt64}
end

function sliding_attack(deltas,sq,occupied)
    attack = UInt64(0)

    for delta in deltas
        s = sq + delta
        while (0 <= s < 64) && (square_distance(s, s - delta) == 1)
            attack |= (UInt64(1) << s)
            if (occupied & (UInt64(1) << s)) != 0 # Stop if we hit an occupied square
                break
            end
            s += delta
        end
    end
    return attack
end

function square_mask(deltas::Vector{Int}, square::Int)
    # Edges: Rank 0, Rank 7, File 0, File 7
    # Exclude the rank/file the square is on
    edges = (((BB_RANKS[1] | BB_RANKS[8]) & ~BB_RANKS[square_rank(square) + 1]) |
             ((BB_FILES[1] | BB_FILES[8]) & ~BB_FILES[square_file(square) + 1]))
    # Note: Julia uses 1-based indexing for BB_RANKS/BB_FILES

    # Get attacks without any occupied squares (the range)
    range = sliding_attack(deltas, square, UInt64(0))

    # The mask is the range excluding the edge squares
    return range & ~edges
end

# Generates all (occupied, attack) pairs for occupied states *within* the given mask
function init_references(mask::UInt64, deltas::Vector{Int}, square::Int)
    refs = Vector{Reference}()
    b = UInt64(0)
    # Loop through all sub-masks of the given mask using the (b-mask)&mask trick
    while true
        attack = sliding_attack(deltas, square, b)
        push!(refs, Reference(b, attack))
        if b == mask    # Stop after mask itself is processed
             break
        end 
        b = (b - mask) & mask
    end
    return refs
end

NUM_MAGICS = UInt64(0)
TABLE = Vector{UInt64}(undef,(1<<MAX_SQUARES)) # Temporary lookup table during search, size 2^SHIFT

function init_stack(square,shift,deltas)    
    STACK = StackFrame[] # Clear previous stack
    max_occupied = square_mask(deltas, square)
    current_mask = UInt64(0)
    last_prefix_bits = 0 # Number of bits in the mask of the previous level

    while true
        bit_to_add = UInt64(1) << msb(max_occupied ⊻ current_mask)
        current_mask |=  bit_to_add

        min_magic = UInt64(1) << max(0, 64 - shift - lsb(current_mask))
        step_magic = UInt64(1) << last_prefix_bits

        if min_magic <= step_magic
            min_magic = UInt64(0)
        end

        mask_bits = 64 - lsb(current_mask) # Number of bits in the current mask (from right)
        max_magic = (mask_bits == 64) ? UInt64(0) : (UInt64(1) << mask_bits)
        is_last_frame = (current_mask == max_occupied)

        refs = init_references(current_mask, deltas, square)
        age = fill!(zeros(UInt64, 1 << shift), typemax(UInt64)) # Initialize with all bits set

        frame = StackFrame(current_mask, mask_bits, last_prefix_bits,
                           is_last_frame, min_magic, step_magic, max_magic,
                           refs, 0, age)

        push!(STACK, frame)

        if is_last_frame
            # Ensure TABLE global is initialized to the correct size
            resize!(TABLE, 1 << shift)
            break # Stop building stack frames
        end

        last_prefix_bits = mask_bits # For the next level
    end
    return STACK
end

# We assume no UInt64 overflow in the range [prefix | frame.min_magic, frame.max_magic)
function divide_and_conquer(prefix::UInt64, depth::Int, STACK, SHIFT)
    # Use the global TABLE and the frame's age array
    frame = STACK[depth + 1] # Julia is 1-based indexing

    # Main loop over magic number candidates at this depth
    # Loop from prefix | frame.min_magic up to frame.max_magic - 1, incrementing by frame.step_magic
    magic = prefix | frame.min_magic
    # Use a standard while loop with a clear termination condition based on max_magic
    while magic < frame.max_magic

        frame.stats += 1

        collided = false
        # Inner loop over references
        for ref in frame.refs
            idx = ((magic * ref.occupied) >> (64 - SHIFT)) + 1 # Shift must be >= number of relevant bits

            if frame.age[idx] != magic
                # First time this 'magic' number hits this index. Store the required attack.
                frame.age[idx] = magic
                TABLE[idx] = ref.attack
            elseif TABLE[idx] != ref.attack
                # Collision detected! Different occupancy masks map to the same index
                # but require different attack bitboards. This 'magic' number is invalid.
                collided = true
                break # Exit the inner loop
            end
        end # end inner loop

        if !collided
            if frame.is_last
                # Found a magic number!
                println("Magic found:$magic")
                break
            else
                # Valid prefix, recurse deeper
                divide_and_conquer(magic, depth + 1,STACK, SHIFT)
            end
        end

        # Move to the next magic candidate for this depth
        magic += frame.step_magic 

        # Safety break for step=0 loop (shouldn't happen unless min=max and step=0?)
        if frame.step_magic == 0 && magic == prefix | frame.min_magic && magic != frame.max_magic
             @error "Step magic is 0 at depth $(depth+1), but min != max. Infinite loop potential."
             break # Prevent infinite loop
        end
    end # end while loop
end

function start(piece,shift,square)
    deltas = []
    if piece == "Rook"
        deltas =  [8, 1, -8, -1, 0]
    elseif piece == "Bishop"
        deltas =  [7, -7, 9, -9, 0 ]
    end

    stack = init_stack(square, shift, deltas)
  
    initial_prefix = UInt64(0)
    initial_depth = 0 # 0-indexed depth

    divide_and_conquer(initial_prefix, initial_depth, stack, shift)
end

function open_JLD2(filename)
    path = "$(pwd())/logic/move_BBs/"
    dicts = Vector{Dict{UInt64,UInt64}}()
    jldopen(path*filename*".jld2", "r") do file
        dicts = file["data"]
    end
    return dicts
end

function main(pos,piece)
    dicts = open_JLD2("$(piece)_dicts")
    dict = dicts[pos+1]
    N = Int(log(2,length(dict)))
    start(piece,N,pos)
end
main(32,"Rook")

#start("Rook",12,0)



