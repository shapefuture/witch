class_name MirrorHash
extends RefCounted

static func canonical(value: Variant) -> Variant:
    if value is Dictionary:
        var pairs: Array = []
        for key in value.keys(): pairs.append({"sort_key": str(key), "type_key": typeof(key), "key": key})
        # sort_custom is NOT stable, so sorting on str(key) alone leaves ties
        # (e.g. int 1 and String "1" both stringify to "1") in an arbitrary,
        # run-dependent order. That would make canonical_json — and therefore every
        # event hash, catalog fingerprint and definition hash — unreproducible.
        # Tie-breaking on typeof gives a total order.
        pairs.sort_custom(func(a, b):
            if str(a["sort_key"]) != str(b["sort_key"]): return str(a["sort_key"]) < str(b["sort_key"])
            return int(a["type_key"]) < int(b["type_key"])
        )
        var out: Dictionary = {}
        for pair in pairs: out[pair["key"]] = canonical(value[pair["key"]])
        return out
    if value is Array:
        var array_out: Array = []
        for item in value: array_out.append(canonical(item))
        return array_out
    if value is float:
        # Godot's JSON parser returns every JSON number as a float, so an int authored
        # in an event payload comes back as 2.0 after a save/load round trip. Normalise
        # whole numbers to int so equivalent values hash identically on both sides.
        var number := float(value)
        if is_finite(number) and number == floor(number) and absf(number) <= 9007199254740992.0:
            return int(number)
        return number
    if value is Object:
        # str(Object) embeds a per-run instance id ("<RefCounted#1234>"), so any hash
        # covering an Object would differ between processes. Reduce to a stable,
        # class-level representation instead. Catalogs are authored as plain
        # dictionaries, so this is a guard rather than a hot path.
        return "<Object:" + str(value.get_class()) + ">"
    return value

static func canonical_json(value: Variant) -> String:
    return JSON.stringify(canonical(value), "", false)

static func sha256(value: Variant) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(canonical_json(value).to_utf8_buffer())
    return context.finish().hex_encode()
