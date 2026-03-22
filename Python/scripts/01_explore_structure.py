import mne 
import pyxdf
from scipy.io import loadmat

# File meant for the data structure exploration.

path = "../../osf_files/lsl_physio_data/ID_001_lsl_data.mat"

data = loadmat(path)

print(type(data), "\n")

print(data.keys(), "\n")