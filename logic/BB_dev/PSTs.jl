using logic

function save_PST(name,data)
    path = "$(pwd())/Engines/PST/"

    io = open(path*name*".txt", "w") do io
        for d in data
        println(io, d)
        end
    end
end

"Pawn square scores from whites perspective"
function PST(::Pawn)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if r == 0 || r == 7 
            #0 and 7 are never reached, double pushing is generally better than single push
            vals[i] = 0
        else
            #encourage pawns off of starting rank and push towards promotion
            vals[i] = 15 * (r-2)
        end
    end
    save_PST("pawn",vals)
end

PST(Pawn())