module ID

## Basic type definitions ##
abstract type Id end

struct AssetId <: Id
    assetid::String
end

struct FieldId <: Id
    fieldid::String
end

end