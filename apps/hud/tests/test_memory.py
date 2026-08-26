import json
import pytest
from app.memory import MemoryError, MemoryStore


def test_traversal_and_outside_are_blocked(config):
    store=MemoryStore(config)
    for path in ("../bad.md","/tmp/bad.md","Other/bad.md","Alfredo/bad.txt"):
        with pytest.raises(MemoryError): store.safe_target(path)


def test_proposal_does_not_write(config):
    store=MemoryStore(config); p=store.propose("Alfredo/note.md","Note","body")
    assert not (config.vault/"Alfredo/note.md").exists(); assert (store.proposals/f"{p['id']}.json").exists()


async def test_approval_writes_once(config):
    store=MemoryStore(config); p=store.propose("Alfredo/note.md","Note","body")
    await store.approve(p["id"]); assert (config.vault/"Alfredo/note.md").read_text()=="# Note\n\nbody\n"
    p2=store.propose("Alfredo/note.md","Other","no")
    with pytest.raises(MemoryError): await store.approve(p2["id"])


def test_symlink_escape_blocked(config,tmp_path):
    outside=tmp_path/"outside"; outside.mkdir(); (config.vault/"Alfredo").symlink_to(outside, target_is_directory=True)
    with pytest.raises(MemoryError): MemoryStore(config).safe_target("Alfredo/bad.md")


def test_selected_context_is_limited_and_safe(config):
    note=config.vault/"Private.md"; note.write_text("secret "*1000)
    selected=MemoryStore(config).read_selected(["Private.md"])
    assert selected[0][0]=="Private.md" and len(selected[0][1])==4000
    with pytest.raises(MemoryError): MemoryStore(config).read_selected(["../outside.md"])
