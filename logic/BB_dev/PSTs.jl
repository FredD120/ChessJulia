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

        if r==3
            #early central pawn control
            if (f==3 || f==4)
                vals[i] += 10
            elseif (f==2 || f==5)
                vals[i] += 5
            end
        end
    end
    save_PST("pawn",vals)
end

function PST(::Knight)
    vals = Vector{Float32}(undef,64)

    for (i,val) in enumerate(vals)
        ind = i - 1
        r = rank(ind)
        f = file(ind)
        
        if (r == 0 || r == 7) || (f == 0 || f == 7)
            #Dissuade knight from being on edge
            vals[i] = -15
        elseif (r == 1 || r == 6) || (f == 1 || f == 6)
            #Neutral if one layer inside edge
            vals[i] = 0
        elseif (r == 2 || r == 5) || (f == 2 || f == 5)
            #Bonus for central control
            vals[i] = 10
        else
            #encourage taking centre early
            vals[i] = 20
        end
    end
    save_PST("knight",vals)
end

PST(Knight())
PST(Pawn())