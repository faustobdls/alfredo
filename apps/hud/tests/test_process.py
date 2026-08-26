import asyncio
import pytest
from app.providers import base


async def test_process_uses_exec_without_shell(monkeypatch,tmp_path):
    seen={}
    class P:
        returncode=0
        async def communicate(self,data): return b"ok",b""
    async def fake(*args,**kwargs): seen.update(args=args,kwargs=kwargs); return P()
    monkeypatch.setattr(asyncio,"create_subprocess_exec",fake)
    code,out,_,_=await base.run_process(["tool","--flag"],"user; rm -rf x",str(tmp_path),1)
    assert code==0 and out=="ok" and seen["args"]==("tool","--flag") and "shell" not in seen["kwargs"]


async def test_timeout_is_raised(monkeypatch,tmp_path):
    class P:
        returncode=None
        async def communicate(self,data): await asyncio.sleep(1)
        def kill(self): pass
        async def wait(self): pass
    async def fake(*a,**k): return P()
    monkeypatch.setattr(asyncio,"create_subprocess_exec",fake)
    with pytest.raises(TimeoutError): await base.run_process(["tool"],"x",str(tmp_path),.001)

