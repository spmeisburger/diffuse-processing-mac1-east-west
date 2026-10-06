"""Script to add geometry information (crystal, and symmetry) to an existing nexus file (e.g. merged.nxs)

python mdx2_embed_geometry.py <input_geometry_file> <output_merged_file>

"""

import sys
from mdx2.io import loadobj, saveobj

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(
            "Usage: python mdx2_embed_geometry.py <input_geometry_file> <output_merged_file>"
        )
        sys.exit(1)
    input_geometry_file = sys.argv[1]
    output_merged_file = sys.argv[2]

    crystal = loadobj(input_geometry_file, "crystal")
    symmetry = loadobj(input_geometry_file, "symmetry")
    saveobj(crystal, output_merged_file, "crystal", append=True)
    saveobj(symmetry, output_merged_file, "symmetry", append=True)
