class_name MirrorPersistence
extends RefCounted

const SAVE_VERSION := 6

static func build_save(engine: MirrorEngine) -> Dictionary:
    return {"schema_version":SAVE_VERSION,"engine_version":MirrorDomain.ENGINE_VERSION,"event_store":engine.event_store.to_dict(),"knowledge":engine.knowledge.to_dict(),"models":engine.models.to_dict(),"evidence":engine.evidence.to_dict(),"operators":engine.operators.to_dict(),"relationships":engine.relationships.to_dict(),"prediction":engine.prediction.to_dict(),"world_state":engine.world_state.duplicate(true),"npc_state":engine.npc_state.duplicate(true),"initial_world_state":engine.initial_world_state.duplicate(true),"initial_npc_state":engine.initial_npc_state.duplicate(true),"action_memory":engine.action_memory.duplicate(true),"catalog":{"revision":engine.catalog_revision,"fingerprint":engine.catalog_fingerprint,"locked":engine.catalog_is_locked}}

static func to_json(engine:MirrorEngine)->String:return JSON.stringify(build_save(engine),"    ",true)

static func load_json(engine:MirrorEngine,text:String)->Dictionary:
    var json:=JSON.new()
    if json.parse(text)!=OK or not json.data is Dictionary:return {"ok":false,"error":"invalid_json"}
    var parsed:Dictionary=json.data
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
    return {"ok":true,"schema_version":migrated["data"]["schema_version"]}

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
    out["schema_version"]=SAVE_VERSION;return {"ok":true,"data":out}
