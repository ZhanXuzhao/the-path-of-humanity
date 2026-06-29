import struct, os, glob

path = r'd:\MyProjects\the-path-of-humanity\assets\art\characters'
os.chdir(path)

for f in sorted(glob.glob('*.png')):
    with open(f, 'rb') as fh:
        fh.read(16)  # skip PNG signature + IHDR chunk header
        w, h = struct.unpack('>II', fh.read(8))
        print(f'{f}: {w}x{h}')
