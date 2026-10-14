class_name MirrorPersistence
extends RefCounted

# Save format 7 seals the body with a checksum (see checksum_of). Saves from before 7 have none
# and still load through migrate(); for those, only the event chain and the projection replay
# stand between a hand-edited file and live state.
const SAVE_VERSION := 7
const CHECKSUM_FROM_VERSION := 7
# Checked on the TEXT before it is parsed, so an oversized file costs no parse and no state.
# Tests lower it temporarily; the default covers roughly 20,000 events at ~2.7 KB each.
static var max_save_bytes: int = 64 * 1024 * 1024

static func build_save(engine: MirrorEngine) -> Dictionary:
    return seal({"schema_version":SAVE_VERSION,"engine_version":MirrorDomain.ENGINE_VERSION,"event_store":engine.event_store.to_dict(),"knowledge":engine.knowledge.to_dict(),"models":engine.models.to_dict(),"evidence":engine.evidence.to_dict(),"operators":engine.operators.to_dict(),"relationships":engine.relationships.to_dict(),"prediction":engine.prediction.to_dict(),"world_state":engine.world_state.duplicate(true),"npc_state":engine.npc_state.duplicate(true),"initial_world_state":engine.initial_world_state.duplicate(true),"initial_npc_state":engine.initial_npc_state.duplicate(true),"action_memory":engine.action_memory.duplicate(true),"catalog":{"revision":engine.catalog_revision,"fingerprint":engine.catalog_fingerprint,"locked":engine.catalog_is_locked}})

static func to_json(engine:MirrorEngine)->String:return JSON.stringify(build_save(engine),"    ",true)

# Adds the body's checksum as its "checksum" field. Tests use it to re-seal a body they changed
# on purpose, so that the check under test is the one that rejects it.
static func seal(body: Dictionary) -> Dictionary:
    body["checksum"] = checksum_of(body)
    return body

# SHA-256 over the body without its "checksum" field. This catches corruption and edits that
# were not re-sealed. It is not a signature: the client holds everything needed to recompute it.
# A forged body that is re-sealed is still refused by the event chain and the projection replay.
static func checksum_of(body: Dictionary) -> String:
    var unsealed := body.duplicate(false)
    unsealed.erase("checksum")
    # Godot's parser returns every JSON number as a float, so an int in the body stringifies
    # differently before and after a save. One parse and stringify cycle puts both sides in the
    # parser's form. This is native JSON work; a GDScript walk of a 13 MB save costs seconds.
    var normal: Variant = JSON.parse_string(JSON.stringify(unsealed))
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(JSON.stringify(normal).to_utf8_buffer())
    return context.finish().hex_encode()

static func is_oversized(text: String) -> bool:
    # A character is never fewer than one byte, so a text longer than the limit is oversized
    # without converting it. Only texts at or under the limit pay for the byte count.
    return text.length() > max_save_bytes or text.to_utf8_buffer().size() > max_save_bytes

# Returns {"ok": bool, "error": String, "legacy": bool}. A save from before the checksum is
# accepted and reported as legacy, so the caller can tell that its body is unverified.
static func verify(data: Dictionary) -> Dictionary:
    if int(data.get("schema_version", 1)) < CHECKSUM_FROM_VERSION:
        return {"ok": true, "error": "", "legacy": true}
    if not data.has("checksum"):
        return {"ok": false, "error": "checksum_missing", "legacy": false}
    if checksum_of(data) != str(data["checksum"]):
        return {"ok": false, "error": "checksum_mismatch", "legacy": false}
    return {"ok": true, "error": "", "legacy": false}

static func load_json(engine:MirrorEngine,text:String)->Dictionary:
    if is_oversized(text):return {"ok":false,"error":"oversized"}
    var json:=JSON.new()
    if json.parse(text)!=OK or not json.data is Dictionary:return {"ok":false,"error":"invalid_json"}
    var parsed:Dictionary=json.data
    if int(parsed.get("schema_version",1))>SAVE_VERSION:return {"ok":false,"error":"future_schema","version":int(parsed["schema_version"])}
    # Integrity is checked on the raw body, before migration, so the checksum covers exactly what
    # was written. Nothing below runs on a save whose checksum does not match.
    var integrity:=verify(parsed)
    if not integrity["ok"]:return {"ok":false,"error":integrity["error"]}
    var migrated:=migrate(parsed)
    if not migrated.get("ok",false):return migrated
    # A rejected load must leave the engine exactly as it was. The previous code answered a
    # projection_mismatch by re-restoring the REJECTED save into the engine, so a forged
    # projection (or events from a save that failed verification) survived in live state.
    var before:=engine._snapshot(true)
    if not engine.restore_from_save(migrated["data"]):return {"ok":false,"error":"restore_rejected"}
    var loaded_projection:=engine.projection_snapshot();var replay:=engine.rebuild_projections_from_event_log(false)
    if not replay.get("ok",false):
        engine._restore_snapshot(before);return {"ok":false,"error":"replay_rejected"}
    if MirrorHash.canonical_json(loaded_projection)!=MirrorHash.canonical_json(replay.get("after",{})):
        engine._restore_snapshot(before);return {"ok":false,"error":"projection_mismatch"}
    return {"ok":true,"schema_version":migrated["data"]["schema_version"],"legacy":integrity["legacy"]}

static func migrate(data:Dictionary)->Dictionary:
    var out:=data.duplicate(true);var version:=int(out.get("schema_version",1))
    if version>SAVE_VERSION:return {"ok":false,"error":"future_schema","version":version}
    if version<2:out["action_memory"]={};version=2
    if version<3:out["prediction"]=out.get("prediction",{"seen_once":{}});version=3
    if version<4:out["npc_state"]=out.get("npc_state",{});out["initial_npc_state"]=out.get("initial_npc_state",out.get("npc_state",{}));version=4
    if version<5:
        out["evidence"]={"items":{},"by_event":{}}
        out["catalog"]={"revision":0,"fingerprint":"","locked":false}
        version=5
    if version<6:
        out["operators"]={"acquired":{},"history":[]}
        version=6
    # Version 7 added the checksum only; its body is otherwise the same as version 6.
    out.erase("checksum")
    out["schema_version"]=SAVE_VERSION;return {"ok":true,"data":out}
