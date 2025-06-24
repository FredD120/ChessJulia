
struct data{T}
    val1::T
    vec::Vector{T}
end

struct inner
    w::Int
    z::Int
end
inner() = inner(1,0)

data(len) = data(inner(),[inner() for _ in 1:len])

val = data(3)

println(val)