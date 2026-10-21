
from setuptools import setup
setup(
    name="IPAM Import Fix",
    app=["ipam_gui_wrapper.py"],
    options={"py2app": {"argv_emulation": False}},
)
