
# pkgs --------------------------------------------------------------------

pkgs <- c("tidyverse", "data.table", "R.matlab")
invisible(lapply(pkgs, library, character.only = TRUE))
message("Loaded :", paste(pkgs, collapse = ", "))


# exploring the data's structure ------------------------------------------

file_path <- "../osf_files/lsl_physio_data/ID_001_lsl_data.mat"

raw_mat <- readMat(file_path) # Reading the first file to discover its properties.

# names() provides [1] "lsl.data" "p"; interesting. It's a list() object of course.
# "p" is just the participant ID, and "lsl.data" contains the three streams.

# It'll be easier on Python I believe.
# 
# Not it's not.
# 
# Let's get the names of the streams.

sapply(1:22, function(i) raw_mat[["lsl.data"]][[1]][[1]][[1]][[18]][[1]][[1]][[i]][[1]][[1]])

# > sapply(1:22, function(i) raw_mat[["lsl# .data"]][[1]][[1]][[1]][[18]][[1]][[1]][[i]][[1]][[1]])
# [1] "confidence"       "norm_pos_x"      
# [3] "norm_pos_y"       "gaze_point_3d_x" 
# [5] "gaze_point_3d_y"  "gaze_point_3d_z" 
# [7] "eye_center0_3d_x" "eye_center0_3d_y"
# [9] "eye_center0_3d_z" "eye_center1_3d_x"
# [11] "eye_center1_3d_y" "eye_center1_3d_z"
# [13] "gaze_normal0_x"   "gaze_normal0_y"  
# [15] "gaze_normal0_z"   "gaze_normal1_x"  
# [17] "gaze_normal1_y"   "gaze_normal1_z"  
# [19] "diameter0_2d"     "diameter1_2d"    
# [21] "diameter0_3d"     "diameter1_3d" 
# 
# Okay so now we have a better idea of what going on here. Python wa such an hassle to do just this holy crap.
# 
# Let's check the rest of the content with the viewer.

vec <- as.numeric(sapply(1:689, function(i) raw_mat[["lsl.data"]][[1]][[1]][[1]][[19]][[1]][[i]][[1]][[1]]))

round(vec - lag(vec), digits = 3)

# Clocks remained synchronized, deviating for no more than 2 ms max.

sapply(1:689, function(i) raw_mat[["lsl.data"]][[1]][[1]][[1]][[19]][[1]][[i]][[1]][[2]])

# those are just the resync done.
# 
# Anyways, I've got to find out the big matrix with the data from the 22 channels.

View(raw_mat[["lsl.data"]][[1]][[1]][[2]])

# Here it is.

names <- c("confidence",       "norm_pos_x",      
           "norm_pos_y",       "gaze_point_3d_x", 
           "gaze_point_3d_y",  "gaze_point_3d_z", 
           "eye_center0_3d_x", "eye_center0_3d_y",
           "eye_center0_3d_z", "eye_center1_3d_x",
           "eye_center1_3d_y", "eye_center1_3d_z",
           "gaze_normal0_x",   "gaze_normal0_y",  
           "gaze_normal0_z",   "gaze_normal1_x",  
           "gaze_normal1_y",   "gaze_normal1_z",  
           "diameter0_2d",     "diameter1_2d",    
           "diameter0_3d",     "diameter1_3d"   )

raw_matrix <- raw_mat[["lsl.data"]][[1]][[1]][[2]]

all_channels <- as_tibble(t(raw_matrix))

colnames(all_channels) <- names

# > all_channels$time_stamps <- raw_mat[["lsl.data"]][[1]][[1]][[3]]
# Error: cannot allocate vector of size 5226.7 Gb
# 
# Almost destroyed my computer. I have to convert to a matrix and transpose first.

timestamp <- t(as.matrix(raw_mat[["lsl.data"]][[1]][[1]][[3]]))

all_channels$timestamp <- timestamp

View(all_channels)

all_channels |> 
  relocate(timestamp,
           .before = 1)

# That's better.
# 
# I need to explore the other parts of the .mat now.
# 
# Let's check [[2]] now.

View(raw_mat)

sapply(1:4, function(i) raw_mat[["lsl.data"]][[2]][[1]][[1]][[18]][[1]][[1]][[i]][[1]][[1]])

# > sapply(1:4, function(i) raw_mat[["lsl# .data"]][[2]][[1]][[1]][[18]][[1]][[1]][[i]][[1]][[1]])
# [1] "ECG"           "Pulse"         "Resp"         
# [4] "GSR_MR_100_xx"

unique(as.vector(raw_mat[["lsl.data"]][[3]][[1]][[2]]))

# I'm not sure what that is at this point. From 0 to 20 unique identifiers?!
# 
# fear_stream
#Each number in the time_series correspond to the following presentation events, and the corresponding timing of the events is stored in time_stamps: 
# 5: offset of information screen
# 6: onset of relaxation period
# 7: offset of relaxation period
# 12: onset of instruction screen
# 13: offset of instruction screen
# 0: onset of fixation cross = baseline 
# 4: offset of fixation cross = baseline 
# 1: onset of stimulus (or catch trial instruction)
# 9: offset of stimulus (or catch trial instruction)
# 2: onset of rating period
# 10: offset of rating period
# 14: onset of “pause” displayed on screen (start of break # questionnaire period)
# 15: offset of “pause” displayed on screen (end of break # questionnaire period)
# 18: onset of goodbye-thankyou screen 
# 19: offset of goodbye-thankyou screen 
# 20: end of experiment 
# 
# Documentation is key I guess.

events_codes <- t(as.matrix(raw_mat[["lsl.data"]][[3]][[1]][[2]]))

events_codes <- as_tibble(events_codes)

events_codes |> 
  group_by(V1) |> 
  summarise(count = n())

# Not doing another matrix, we'll process that with Python after.

events_time <- as.vector(raw_mat[["lsl.data"]][[3]][[1]][[3]])

# Here are the timestamps for each events.

events_time - lag(events_time)

# Ok, I guess I can just go on Python and process the data now that I've taken a good look at the structure of the file.
