#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = '/Users/subha/Downloads/VALUENEX/NearbyInteractionUWB/NIPeekaboo.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main group
main_group = project.main_group['NIPeekaboo']

# Check if DistanceErrorTracker.swift already exists
distance_tracker_exists = main_group.files.any? { |file| file.path == 'DistanceErrorTracker.swift' }

if distance_tracker_exists
  puts "DistanceErrorTracker.swift already exists in the project"
else
  # Add the file reference
  file_ref = main_group.new_reference('DistanceErrorTracker.swift')
  
  # Add to the main target's compile sources
  main_target = project.targets.find { |t| t.name == 'NIPeekaboo' }
  main_target.source_build_phase.add_file_reference(file_ref)
  
  puts "Added DistanceErrorTracker.swift to the project"
end

# Save the project
project.save

puts "Project saved successfully"