# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place - Suite 330, Boston, MA 02111-1307, USA, or go to
# http://www.gnu.org/copyleft/lesser.txt.
#-----------------------------------------------------------------------------
# Name		: su2kt.rb
# Description	: Export model,su2kt_lights & cameras for current view or for all SU pages into Kerkythea
# Menu Item:		Plugins\kerkythea Exporter
# Author:		Tomasz Marek
# Help:		Stefan Jaensch, Tim Crandall, Lee Anderson - THANK YOU
#			Initialy based on SU exporters: SU2POV by Didier Bur and OGRE exporter by Kojack
# Usage:		Copy script to PLUGINS folder in SketchUp folder, run SU, go to Plugins\Kerkythea exporter
# Date:		9th October 2010
# Type:		Exporter
# Version:
#         3.17BOKU: Christoph Graf(christoph.graf@boku.ac.at)
#				- Fixed Bug with alpha channel (now also alpha channels in main materials/components are correctly exported)
#				- Fixed Bug that pngs are correctly be used as textures
#   	  3.17+ Bug Fix release:
#			   - KST path bug fix (6th Aug 2013)
#		       - FM_material bug fixed
#		       - wrong normals for flipped component fixed
#		  3.16 - IES lights support added by Lee Anderson
#					- FaceMe animation fixed
#					- attenuation options added to spot and pointlights (initiative of Claes Jakobsson)
# 		  3.15 - bugfix for full frame animation export with texures
#				- all Photomatched textures exported correctly
#				- emiters (Emit[..] and EmitFake) use material colour
#		  3.1 - Scenes export (su animate support) introduced by Tim Crandall, Alpha channell in PNG and TIFimages supported
#			   Full model per frame export(proper_animation script), selection of rendering method for animation & scene export
#			   Instanced export and proxy creation, EMITER bug fixed
#		  3.07 Improvements by Stefan Jaensch
#			UV-Phtotomatch-Bug fixed. Textures are now in right angle and position if model/component is transformed.
#			Read color from KT-Material in extract_kt_material().
#			Encreased performance on export_face() dramatically by replacing hashtables with arrays and tempvars.
#		  3.06 - XML compliant replacement for "&", "<", ">", "\"" "'" in names by Nicetuna
#		  3.05 - Mac compatibile version
#		  3.0 - Memory leak bug fixed, wrong date bug fixed (KT2007),intensity of colours back to 1.0,
#			KT icons added, model opening in KT after export, missing GIF textures bug fixed,
#			KT library materials import added, backface material exported when no front material specified
#			Time bug for non GMT location fixed, photomatched faces\textures exported as a selection,
#			Tool for placing spot & pointlights added
#		  2.21 - Flipped images and missing BMP textures bugs fixed
#		  2.2 - Bugfixes, automatic activation of lights,animated lights status added,
#			FakeEmit, Emit[power] material added, frame numbers inproved,
#			Animation settings stored with model, Rendering settings from main XML are preserved
#			SU2KT is now Mac enabled (Thanks to povlhp)
#		  2.11 - SU 6 fixes by Wehby
#		  2.1  - Animation export added, Face Me Components Export for current view
#		  2.01 - Selection, Clay export added, Currnet View exported
#		  2.0  - All geometry and textures exported and nested lights supported
#		  1.1  - sun and phisical sky added, parallel views exported
#		  1.01 - bugfix - script is exporting all perspectives, won't stop on parallel views
#-----------------------------------------------------------------------------

require 'sketchup.rb'
require 'chunky_png'

class SU2KT

	FRONTF = "Front Face"

# ---- Settings and global variables ----- #

def SU2KT::reset_global_variables

	@n_pointlights=0
	@n_spotlights=0
	@n_cameras=0
	@face=0
	@scale = 0.0254
	@copy_textures = true
	@export_materials = true
	@export_meshes = true
	@export_lights = true
	@instanced=true
	@model_name=""
	@textures_prefix = "TX_"
	@texture_writer=Sketchup.create_texture_writer
	@model_textures={}
	@count_tri = 0
	@count_faces = 0
	@lights = []
	@materials = {}
	@fm_materials = {}
	@components = {}
	@selected=false
	@exp_distorted = false
	@exp_default_uvs = false
	@clay=false
	@animation=false
	@export_full_frame=false
	@frame=0
	@parent_mat=[]
	@fm_comp=[false] #first level in a objects tree - not FM
	@status_prefix = ""   # Identifies which scene is being processed in status bar
	@scene_export = false # True when exporting a model for each scene
	@status_prefix=""

	@ds = (ENV['OS'] =~ /windows/i) ? "\\" : "/" # directory separator for Windows : OS X

end

def self.ds
	@ds
end

##### ------  Export ------ ######

def SU2KT::export

	SU2KT.reset_global_variables

	@selected=true if Sketchup.active_model.selection.length > 0
	continue=SU2KT.export_options_window
	return if continue==false
	SU2KT.file_export_window
	return if @model_name==""

	model = Sketchup.active_model
	out = File.new(@export_file,"w")
	@path_textures=File.dirname(@export_file)

	start_time=Time.new
	SU2KT.export_global_settings(out)

	entity_list=model.entities
	entity_list=model.selection if @selected==true

	SU2KT.find_lights(entity_list,Geom::Transformation.new)

	SU2KT.write_sky(out)

	SU2KT.export_meshes(out,entity_list) if @instanced==false
	SU2KT.export_instanced(out,entity_list) if @instanced==true

	SU2KT.export_current_view(model.active_view, out)
	@n_cameras=1

	model.pages.each do |p|
		SU2KT.export_page_camera(p, out) if p.use_camera?
	end

	SU2KT.export_lights(out) if @export_lights==true
	SU2KT.write_sun(out)
	SU2KT.finish_close(out)
	stext=SU2KT.write_textures

	result=SU2KT.report_window(start_time,stext)
	SU2KT.kt_start if result==6

	SU2KT.reset_global_variables

end

def SU2KT::export_options_window

	export_selection = %w[Yes No].join("|")
	export_meshes = %w[Yes No].join("|")
	export_lights = %w[Yes No].join("|")
	export_clay = %w[Yes No].join("|")
	export_distorted= %w[Yes No].join("|")
	export_default_uvs= %w[Yes No].join("|")
	export_instanced= %w[Yes No].join("|")

	dropdowns=[]
	values=[]
	prompts=[]
	if @selected==true
		dropdowns.push export_selection
		prompts.push "Export selection ONLY   "
		values.push "Yes"
		add_item=1
	else
		add_item=0
	end

	dropdowns+=[export_meshes,export_lights,export_clay,export_distorted,export_default_uvs,export_instanced]
	prompts+=["Geometry","Lights","Clay","Photomatched                       ","Default UVs","Instanced"]
	values+=SU2KT.get_export_settings

	results = inputbox prompts,values, dropdowns, "Export options"
	return false if not results
	SU2KT.set_export_settings(results[add_item .. results.length])

	if (add_item==1 &&  results[0]=="Yes")
		@selected=true
	else
		@selected=false
	end
	@export_meshes = false if results[0+add_item]=="No"
	@export_lights = false if results[1+add_item]=="No"
	(@clay=true;@copy_textures = false) if results[2+add_item]=="Yes"
	@exp_distorted = true if results[3+add_item]=="Yes"
	@exp_default_uvs = true if results[4+add_item]=="Yes"
	@instanced = false if results[5+add_item]=="No"
	true
end

def SU2KT::get_export_settings
	model=Sketchup.active_model
	dict_name="su2kt_export_settings"
	exist = model.attribute_dictionary dict_name
	values=[]
	values.push(exist ? model.get_attribute(dict_name, "export_meshes") : "Yes")
	values.push(exist ? model.get_attribute(dict_name, "export_lights") : "Yes")
	values.push(exist ? model.get_attribute(dict_name, "export_clay") : "No")
	values.push(exist ? model.get_attribute(dict_name, "export_distorted") : "No")
	values.push(exist ? model.get_attribute(dict_name, "export_default_uvs") : "Yes")
	values.push(exist ? model.get_attribute(dict_name, "export_instanced") : "No")
	return values
end

def SU2KT::set_export_settings(values)
	model=Sketchup.active_model
	dict_name="su2kt_export_settings"
	model.set_attribute(dict_name,"export_meshes",values[0])
	model.set_attribute(dict_name,"export_lights",values[1])
	model.set_attribute(dict_name,"export_clay",values[2])
	model.set_attribute(dict_name,"export_distorted",values[3])
	model.set_attribute(dict_name,"export_default_uvs",values[4])
	model.set_attribute(dict_name,"export_instanced",values[5])

end

def SU2KT::file_export_window

	export_text="Export Model to Kerkythea"
	export_text="Export SELECTION to Kerkythea" if @selected==true

	model = Sketchup.active_model

	model_filename = File.basename(model.path)
		if model_filename!=""
			model_name = model_filename.split(".")[0]
			model_name += ".xml"
		else
			model_name = "Untitled.xml"
		end

		@export_file=UI.savepanel(export_text, "" , model_name)

		return if @export_file==nil

		if @export_file==@export_file.split(".")[0]
			@export_file+=".xml"
		end
		@model_name=File.basename(@export_file)
		@model_name=@model_name.split(".")[0]

		if @export_file.length != @export_file.unpack('U*').length
			UI.messagebox("The file path and/or the file name contains non-latin characters.\nPlease save in a different folder.\nI am working on a solution to this issue.")
			SU2KT.file_export_window
		end

end

def SU2KT::report_window(start_time,stext)

	end_time=Time.new
	elapsed=end_time-start_time
	time=" exported in "
		(time=time+"#{(elapsed/3600).floor}h ";elapsed-=(elapsed/3600).floor*3600) if (elapsed/3600).floor>0
		(time=time+"#{(elapsed/60).floor}m ";elapsed-=(elapsed/60).floor*60) if (elapsed/60).floor>0
		time=time+"#{elapsed.round}s. "

	SU2KT.status_bar(stext+time+" Triangles = #{@count_tri}")
	export_text="Model & Lights saved in file:\n"
	export_text="Selection saved in file:\n" if @selected==true
	result=UI.messagebox export_text + @export_file + "\n\nCameras exported: " + @n_cameras.to_s + "\n" + @sunexport + "Lights exported:\nPointlights: " + @n_pointlights.to_s +  "   Spotlights: " + @n_spotlights.to_s+"\n\nOpen exported model in Kerkythea?",MB_YESNO

end

def SU2KT::render_animation

	kt_path=SU2KT.get_kt_path
	return if kt_path==nil
	script_file_path=@export_file
	script_file_path=File.join(script_file_path.split(@ds))

	if (ENV['OS'] =~ /windows/i)
		batch_file_path=File.dirname(kt_path)+@ds+"start.bat"
		batch=File.new(batch_file_path,"w")
		batch.puts "cd \"#{File.dirname(script_file_path)}\""
		batch.puts "start \"\" \"#{kt_path}\" \"#{File.basename(script_file_path)}\""
		batch.close
		UI.openURL(batch_file_path)
	else #MAC solution
		Thread.new do
			system(`#{kt_path} "#{script_file_path}"`)
		end
	end

end

def SU2KT::kt_start

	kt_path=SU2KT.get_kt_path
	return if kt_path==nil

	script_file_path=File.dirname(kt_path)+@ds+"start.kst"
	script_file_path=File.join(script_file_path.split(@ds))
	script=File.new(script_file_path,"w")
	script.puts "message \"Load #{@export_file}\""
	SU2KT.generate_sun(script)
	script.close

	if (ENV['OS'] =~ /windows/i)
		batch_file_path=File.dirname(kt_path)+@ds+"start.bat"
		batch=File.new(batch_file_path,"w")
		batch.puts "start \"\" \"#{kt_path}\" \"#{script_file_path}\""
		batch.close
		UI.openURL(batch_file_path)
	else
		Thread.new do
			system(`#{kt_path} "#{script_file_path}"`)
		end
	end

	#cmd = "\"" + sketchupDir + "\\plugins\\SuRDebug\\SuRDebug.exe\" --suver=#{suVer}"
	#puts cmd
	#systhr = Thread.new(){`#{cmd}`}
	#Pecan suggested method

	rescue Errno::EACCES
		script_file_path.tr!('/',@ds)
		script_file_path.tr!("\\",@ds)
		UI.messagebox "A file : '#{script_file_path}' could not be created.\nPlease change permissions for the folder\\file.\nKerkythea won't open automatically."
		return nil

end

def SU2KT::get_kt_path

	path=File.dirname(__FILE__)+@ds+"kt_path.txt"
	find_kt=false

	path.tr!('/',@ds)
	path.tr!("\\",@ds)

	if File.exist?(path)  #check if kt_path.txt exists
		path_file=File.new(path,"r")
		kt_path=path_file.read  #contents of kt_path.txt
		path_file.close
		if SU2KT.kt_path_valid?(kt_path)
			return kt_path
		else
			find_kt=true
		end
	else
		find_kt=true
	end

	if find_kt==true
		kt_path=UI.openpanel("LOCATE Kerkythea program , PLEASE","","")
		return nil if kt_path==nil
		return nil if !SU2KT.kt_path_valid?(kt_path)
		path_file=File.new(path,"w") if kt_path
		path_file.write(kt_path) if kt_path
		path_file.close if kt_path

	end

	if SU2KT.kt_path_valid?(kt_path)
		return kt_path
	else
		return nil
	end

	rescue Errno::EACCES
		UI.messagebox "A file : '#{path}' could not be created.\nPlease change permissions for the folder\\file."
		return (SU2KT.kt_path_valid?(kt_path) ? kt_path : nil)

end

def SU2KT::kt_path_valid?(kt_path)
	(File.exist?(kt_path) and (File.basename(kt_path).upcase.include?("KERKYTHEA"))) #check if the path to kt is valid
end

# ---------------- About message ------------- #
def SU2KT::about
UI.messagebox("SU2KT version 3.17BOKU 12th Februar 2014
Freeware SketchUp Exporter to Kerkythea
Author: Tomasz MAREK
Modified: Christoph GRAF

USAGE:
1. Any component called 'su2kt_pointlight' or 'su2kt_spotlight'
    will turn into the corresponding light type. To edit it
    please select one and use context menu.
2. To export model to Kerkythea
   - go to Plugins\\Kerkythea Exporter and select 'Export model'
3. To assign Thin Glass shader to material
   add 'TG_' prefix to material's name.
4. To make material appear always bright call it 'EmitFake'
5. To turn material into light call it 'Emit[#]'
    where \# stands for power of light (8=~100W)
7. KT Material Libaries can be used now directy in SU.
    Please use KT Material Import tools.
8. Creates ies light when ies filename is used for the name of a spotlight,
   for example, a spotlight named 6.ies. Make sure the light is present,
   in Kerkythea\ies\.

For further information please visit
Kerkythea Website & Forum - www.kerkythea.net" , MB_MULTILINE , "SU2KT - Model Exporter to Kerkythea")

end

# -----------Extract the camera parameters of the current view ------------ ###
def SU2KT::export_current_view(v,out)

	h=v.vpheight
	w=v.vpwidth
	user_camera=v.camera
	user_pers=user_camera.perspective?
	user_eye=user_camera.eye

	user_x=user_camera.xaxis
	user_y=user_camera.yaxis
	user_z=user_camera.zaxis

	if user_pers==true
		user_foc = user_camera.focal_length
	else
		user_foc = user_camera.height.to_m
	end

	if (@animation == true or @scene_export == true)
		w_x_h = @resolution
	else
		w_x_h = w.to_s + "x" + h.to_s
	end

	SU2KT.write_camera("\#\# Current View \#\#", user_eye, user_x, user_y, user_z, w_x_h, user_foc, out, user_pers)

end

# ----------------------------------------Extract the camera parameters of a particular page
def SU2KT::export_page_camera(p,out)

	h = Sketchup.active_model.active_view.vpheight
	w = Sketchup.active_model.active_view.vpwidth
	user_camera = p.camera
	user_pers = user_camera.perspective?
	user_eye = user_camera.eye
	user_x = user_camera.xaxis
	user_y = user_camera.yaxis
	user_z = user_camera.zaxis

	if( user_pers == true )
		user_foc = user_camera.focal_length
	else
		user_foc = user_camera.height.to_m
	end

	w_x_h = w.to_s + "x" + h.to_s

	(SU2KT.write_camera p.name, user_eye, user_x, user_y, user_z, w_x_h, user_foc, out, user_pers)

end

#---------------- Save camera to file ------------------------#

def SU2KT::write_camera( p, user_eye, user_x, user_y, user_z, w_x_h, user_foc, out, pers)


projection="Planar" if pers==true
projection="Parallel" if pers==false
user_foc=user_foc/36 if pers==true

out.puts "<Object Identifier=\"./Cameras/"+ SU2KT.normalize_text(p) +"\" Label=\"Pinhole Camera\" Name=\""+ SU2KT.normalize_text(p) +"\" Type=\"Camera\">"
out.puts  "<Parameter Name=\"Focal Length\" Type=\"Real\" Value=\"" + "%.4f" % (user_foc) + "\" />"
out.puts  "<Parameter Name=\"Resolution\" Type=\"String\" Value=\"#{w_x_h}\"/>"

cx=user_eye.x.to_m.to_f
cy=user_eye.y.to_m.to_f
cz=user_eye.z.to_m.to_f

rvx=user_x.x.to_cm.to_f
rvy=user_x.y.to_cm.to_f
rvz=user_x.z.to_cm.to_f

dvx=0.0-user_y.x.to_cm.to_f
dvy=0.0-user_y.y.to_cm.to_f
dvz=0.0-user_y.z.to_cm.to_f

tvx=user_z.x.to_cm.to_f
tvy=user_z.y.to_cm.to_f
tvz=user_z.z.to_cm.to_f

	out.puts "<Parameter Name=\"Frame\" Type=\"Transform\" Value=\"" + "%.4f" % (rvx) + " " + "%.4f" % (dvx) + " " + "%.4f" % (tvx) + " " + "%.4f" % (cx)
	out.puts "%.4f" % (rvy) + " " + "%.4f" % (dvy) + " " + "%.4f" % (tvy)+ " " + "%.4f" % (cy)
	out.puts "%.4f" % (rvz) + " " + "%.4f" % (dvz) + " " + "%.4f" % (tvz)+ " " + "%.4f" % (cz)
	out.puts "\"/>"
	out.puts "<Parameter Name=\"Focus Distance\" Type=\"Real\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Projection\" Type=\"String\" Value=\"#{projection}\"/>"
	out.puts "</Object>"

@n_cameras +=1

end

#### --------- Lights export main routine --------- ########

def SU2KT::export_lights(out)

	SU2KT.status_bar("Exporting lights...")
	SU2KT.write_point_lights(out)
	SU2KT.write_spotlights(out)

end

### ---- Find light by name ---  #####

def SU2KT::find_lights(entity_list,trans)

	for e in entity_list

		if e.class == Sketchup::Group and e.layer.visible? and e.visible?
			SU2KT.find_lights(e.entities, trans*e.transformation)
		end

		if e.class == Sketchup::ComponentInstance and e.layer.visible? and e.visible?

			def_name=e.definition.name

			if (def_name.include? "su2" and def_name.include? "_spotlight") or (def_name.include? "su2" and def_name.include?"_pointlight")
				transold=trans
				trans=trans*e.transformation
				@lights = @lights + [[def_name,e,trans]]
				trans=transold
			else
				SU2KT.find_lights(e.definition.entities, trans*e.transformation)
			end

		end

	end
end

# ----------------------------------- Outputs omni-directionnal light sources (point_lights)
def SU2KT::write_point_lights(out)

	@lights.each do |lights|

		if lights[0].include? "_pointlight"
		glob_trans=lights[2]
		e=lights[1]

		SU2KT.set_default_pointlight(e,nil)

			# get its color and power
			params = SU2KT.get_light_params (e)

			if (params[4].length>1 and @animation==true)
				state=SU2KT.check_animate_state(params[4])
				params[2]=state if state!="DEF"
			end
			# Light status is "On"
			params[2].upcase!

			if params[2] == "ON"

			attenuation = (params[5] == nil ? "Inverse Square" : params[5])

			trans=glob_trans.to_a #light location

			x = trans[12]
			y = trans[13]
			z = trans[14]

			ptx=glob_trans.xaxis
			pty=glob_trans.yaxis
			ptz=glob_trans.zaxis

			out.puts "<Object Identifier=\"./Lights/" + SU2KT.normalize_text(params[0]) + "\" Label=\"Default Light\" Name=\"" + SU2KT.normalize_text(params[0]) + "\" Type=\"Light\">"
			out.puts "<Object Identifier=\"Omni Light\" Label=\"Omni Light\" Name=\"\" Type=\"Emittance\">"
			out.puts "<Object Identifier=\"./Radiance/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
			out.puts "<Parameter Name=\"Color\" Type=\"RGB\" Value=\"" + params[3] + "\" />"
			out.puts "</Object>"
			out.puts "<Parameter Name=\"Attenuation\" Type=\"String\" Value=\"#{attenuation}\"/>"
			out.puts "</Object>"
			out.puts "<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"1\"/>"
			out.puts "<Parameter Name=\"Shadow\" Type=\"Boolean\" Value=\"1\"/>"
			out.puts "<Parameter Name=\"Soft Shadow\" Type=\"Boolean\" Value=\"1\"/>"
			out.puts "<Parameter Name=\"Negative Light\" Type=\"Boolean\" Value=\"0\"/>"
			out.puts "<Parameter Name=\"Global Photons\" Type=\"Boolean\" Value=\"1\"/>"
			out.puts "<Parameter Name=\"Caustic Photons\" Type=\"Boolean\" Value=\"1\"/>"
			out.puts "<Parameter Name=\"Multiplier\" Type=\"Real\" Value=\"" + params[1].to_s + "\"/>"
			out.puts "<Parameter Name=\"Frame\" Type=\"Transform\" Value=\"" + "%.4f" % (ptx.x) + " " + "%.4f" % (pty.x) + " " + "%.4f" % (0.0-ptz.x) + " " + "%.4f" % (x.to_m)
			out.puts "%.4f" % (ptx.y) + " " + "%.4f" % (pty.y) + " " + "%.4f" % (0.0-ptz.y) + " " + "%.4f" % (y.to_m)
			out.puts "%.4f" % (ptx.z) + " " + "%.4f" % (pty.z) + " " + "%.4f" % (0.0-ptz.z) + " " + "%.4f" % (z.to_m)
			out.puts "\"/>"
			out.puts "<Parameter Name=\"Focus Distance\" Type=\"Real\" Value=\"1\"/>"
			out.puts "<Parameter Name=\"Radius\" Type=\"Real\" Value=\"0\"/>"
			out.puts "<Parameter Name=\"Shadow Color\" Type=\"RGB\" Value=\"0 0 0\"/>"
			out.puts "</Object>"

			@n_pointlights +=1

		end

	end
end
end

# -------------Outputs spotlight sources ----------------------  ###
def SU2KT::write_spotlights(out)

params = []
rad_fall_tight = []

@lights.each do |lights|

	if lights[0].include? "_spotlight"
		glob_trans=lights[2]
		e=lights[1]

		SU2KT.set_default_spotlight(e,nil)
		params = SU2KT.get_light_params (e)

		if (params[4].length>1 and @animation==true)
				state=SU2KT.check_animate_state(params[4])
				params[2]=state if state!="DEF"
		end

	params[2].upcase!

	if( params[2] == "ON" )	# Light status is "On"

	rad_fall_tight = (SU2KT.get_spotlight_rad_fall_tight e)

	attenuation = (params[5]==nil ? "Inverse Square" : params[5])

	trans = glob_trans.to_a

	x = trans[12]
	y = trans[13]
	z = trans[14]

	ptx=glob_trans.xaxis
	pty=glob_trans.yaxis
	ptz=glob_trans.zaxis

	out.puts "<Object Identifier=\"./Lights/" + SU2KT.normalize_text(params[0]) + "\" Label=\"Default Light\" Name=\"" + SU2KT.normalize_text(params[0]) + "\" Type=\"Light\">"

	if SU2KT.normalize_text(params[0]).upcase.include?(".IES")  #this is an IES Light  Lee Anderson
		out.puts "<Object Identifier=\"IES Light\" Label=\"IES Light\" Name=\"\" Type=\"Emittance\">"
	else #this is a Spot Light
		out.puts "<Object Identifier=\"Spot Light\" Label=\"Spot Light\" Name=\"\" Type=\"Emittance\">"
	end

	out.puts "<Object Identifier=\"./Radiance/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "<Parameter Name=\"Color\" Type=\"RGB\" Value=\"" + params[3] + "\" />"
	out.puts "</Object>"

	if SU2KT.normalize_text(params[0]).upcase.include?(".IES") then  #this is an IES Light Lee Anderson
		path=SU2KT.get_kt_path
		path=File.join(path.split(@ds))	
		path=File.dirname(path)+"/ies/"+SU2KT.normalize_text(params[0])
		out.puts ("<Parameter Name=\"Filename\" Type=\"File\" Value=\""+path+"\"/>")
		out.puts "<Parameter Name=\"Attenuation\" Type=\"String\" Value=\"Inverse Square\"/>"
	else #this is a SpotLight
		out.puts "<Parameter Name=\"Attenuation\" Type=\"String\" Value=\"#{attenuation}\"/>"
		falloff = rad_fall_tight[1].to_s
		out.puts "<Parameter Name=\"Fall Off\" Type=\"Real\" Value=\"" + falloff + "\"/>"
		radius = rad_fall_tight[0].to_s
		out.puts "<Parameter Name=\"Hot Spot\" Type=\"Real\" Value=\"" + radius + "\"/>"
	end

	out.puts "</Object>"
	out.puts "<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Shadow\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Soft Shadow\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Negative Light\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "<Parameter Name=\"Global Photons\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Caustic Photons\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Multiplier\" Type=\"Real\" Value=\"" + params[1].to_s + "\"/>"
	out.puts "<Parameter Name=\"Frame\" Type=\"Transform\" Value=\"" + "%.4f" % (ptx.x) + " " + "%.4f" % (pty.x) + " " + "%.4f" % (0.0-ptz.x) + " " + "%.4f" % (x.to_m)
	out.puts "%.4f" % (ptx.y) + " " + "%.4f" % (pty.y) + " " + "%.4f" % (0.0-ptz.y) + " " + "%.4f" % (y.to_m)
	out.puts "%.4f" % (ptx.z) + " " + "%.4f" % (pty.z) + " " + "%.4f" % (0.0-ptz.z) + " " + "%.4f" % (z.to_m)
	out.puts "\"/>"
	dist=e.get_attribute("su2kt", "distance")
	dist=1 if dist==nil
	out.puts "<Parameter Name=\"Focus Distance\" Type=\"Real\" Value=\"#{dist}\"/>"
	out.puts "<Parameter Name=\"Radius\" Type=\"Real\" Value=\"0\"/>"
	out.puts "<Parameter Name=\"Shadow Color\" Type=\"RGB\" Value=\"0 0 0\"/>"
	out.puts "</Object>"

	@n_spotlights +=1

	end

	end
end

end

# ----------------------------------- Get the radius, falloff and tightness parameters of a spotlight
def SU2KT::get_spotlight_rad_fall_tight( light )

dict_name="su2kt"
dicts=light.attribute_dictionaries
ret = []
if( dicts != nil and dicts[dict_name] )
	spotlight_rad = light.get_attribute(dict_name, "radius").to_f
	fall = light.get_attribute(dict_name, "falloff").to_f
	else
	ret = ["0", "100"]
end
# default values if not set by the user
if( spotlight_rad == nil )
	ret = ["0", "100"]
	else
	ret = [spotlight_rad, fall]
end
return ret
end

# ----------------------------------- Set the color and power of selected pointlight
def SU2KT::set_pointlight_params(e,dist)

	# Get the pointlight color, even if not already set by the user
	if e.material != nil
		pointlight_color = e.material.display_name
	else
		pointlight_color = "White"
	end

	# Retrieve color and power if any
	SU2KT.set_default_pointlight(e,dist)

	dict_name="su2kt"
	dict_key_name = e.get_attribute(dict_name, "name")
	dict_key_power = e.get_attribute(dict_name, "power")
	dict_key_status = e.get_attribute(dict_name, "status")
	dict_key_animate = e.get_attribute(dict_name, "animate")

	 dict_key_attenuation = e.get_attribute(dict_name, "attenuation")

#Dialog box 1: Name, power
	status_list = %w[On Off].join("|")
	attenuation_list = "None|Inverse|Inverse Square"
	dropdowns = [status_list,"","","","",attenuation_list] #[status_list]
	prompts=["Status  ","Light name  ", "Light power  ","Animation keys ", "Key sample: ","Attenuation "]
	values=[dict_key_status, dict_key_name, dict_key_power,dict_key_animate,"1[On]-4[Off]-7[On]                     ",dict_key_attenuation]
	results = inputbox prompts, values, dropdowns, "LIGHT COLOUR: " + pointlight_color
	return nil if not results
	dict_key_name = results[1]
	dict_key_status = results[0]
	dict_key_power = results[2]
	dict_key_animate = results[3]

	 dict_key_attenuation = results[5]

	e.attribute_dictionary(dict_name, true)
	e.set_attribute(dict_name,"name",dict_key_name)
	e.set_attribute(dict_name,"power",dict_key_power)
	e.set_attribute(dict_name,"status",dict_key_status)
	e.set_attribute(dict_name,"animate",dict_key_animate)
	e.set_attribute(dict_name,"attenuation",dict_key_attenuation)
end

# ----------------------------------- Set the parameters of selected spotlight
def SU2KT::set_spotlight_params(e,dist)

	SU2KT.set_default_spotlight(e,dist)
	dict_name="su2kt"
	dict_key_name = e.get_attribute(dict_name, "name")
	dict_key_power = e.get_attribute(dict_name, "power")
	dict_key_status = e.get_attribute(dict_name, "status")
	dict_key_radius = e.get_attribute(dict_name, "radius")
	dict_key_falloff = e.get_attribute(dict_name, "falloff")
	dict_key_animate = e.get_attribute(dict_name, "animate")
	dict_key_attenuation = e.get_attribute(dict_name, "attenuation")
	dict_key_attenuation = "Inverse Square" if dict_key_attenuation==nil
	dict_key_radius =@spothot if@spothot!=nil
	dict_key_falloff = @spotoff if @spotoff!=nil
# Get color of spotlight, even if not set by the user
	if e.material != nil
	spotlight_color = e.material.display_name
	else
	spotlight_color = "White"
	end
#Dialog box 1:
	status_list = %w[On Off].join("|")
	attenuation_list = "None|Inverse|Inverse Square"
	dropdowns = [status_list,"","","","","","",attenuation_list] #[status_list]
	prompts=["Status  ","Light name  ","Light power ", "Hot Spot ", "Falloff  ", "Animation keys  ","Key sample: ","Attenuation "]
	values=[dict_key_status,dict_key_name, dict_key_power, dict_key_radius, dict_key_falloff,dict_key_animate,"1[On]-4[Off]-7[On]                   ",dict_key_attenuation]
	results = inputbox prompts,values, dropdowns, "Spotlight Color: " + spotlight_color
	return nil if not results
	dict_key_name = results[1]
	dict_key_power = results[2]
	dict_key_radius = results[3]
	dict_key_falloff = results[4]
	dict_key_status = results[0]
	dict_key_animate=results[5]
	dict_key_attenuation = results[7]

	dict_name="su2kt"
	e.attribute_dictionary(dict_name, true)
	e.set_attribute(dict_name,"name",dict_key_name)
	e.set_attribute(dict_name,"power",dict_key_power)
	e.set_attribute(dict_name,"status",dict_key_status)
	e.set_attribute(dict_name,"radius",dict_key_radius)
	e.set_attribute(dict_name,"falloff",dict_key_falloff)
	e.set_attribute(dict_name,"animate",dict_key_animate)
	e.set_attribute(dict_name,"attenuation",dict_key_attenuation)
	@spothot = dict_key_radius
	@spotoff = dict_key_falloff

end

def SU2KT::get_object_color (obj)
	if (obj.material == nil)
		col = Sketchup::Color.new [255,255,255]
	else
		col = obj.material.color
	end
return col
end

# ---- Get the params of light ----- #
# ---- returns an array -------------#
def SU2KT::get_light_params( light )

	dict_name="su2kt"
	dict=light.attribute_dictionary "su2kt"

	if dict != nil
		light_name = light.get_attribute(dict_name, "name")
		pow = light.get_attribute(dict_name, "power").to_f
		status = light.get_attribute(dict_name, "status")
		animate = light.get_attribute(dict_name, "animate")
		attenuation = light.get_attribute(dict_name, "attenuation")
	else
		ret = ["noname","1","On","1.0 1.0 1.0"," ","Inverse Square"]
	end

	# get color of light
		col = (SU2KT.get_object_color light)
	# Component found, real values or default values if not set by the user
		if( col != nil)
			red = (col.red / 255.0)
			green = (col.green / 255.0)
			blue = (col.blue / 255.0)
			return_col = red.to_s + " " + green.to_s + " " + blue.to_s
			ret = [light_name, pow, status, return_col,animate,attenuation]
		else
			ret = ["noname","1","On","1.0 1.0 1.0"," ","Inverse Square"]
		end
	return ret
end

### ---- set default pointlight values if not present --- ####

def SU2KT::set_default_pointlight(e,dist)

	dict_name="su2kt"

	if !e.attribute_dictionary dict_name
		if e.attribute_dictionary "su2pov"
			dict_key_name = e.get_attribute("su2pov", "name")
			dict_key_power = e.get_attribute("su2pov", "power")
			dict_key_status = e.get_attribute("su2pov", "status")
		else #default values
		dict_key_name = "Pointlight"
		dict_key_power = "%.1f" % (0.7*dist*dist) if dist
		dict_key_status = "On"
		end
	dict_key_animate = " "
	dict_key_attenuation = "Inverse Square"
	e.attribute_dictionary(dict_name, true)
	e.set_attribute(dict_name,"name",dict_key_name)
	e.set_attribute(dict_name,"power",dict_key_power)
	e.set_attribute(dict_name,"status",dict_key_status)
	e.set_attribute(dict_name,"animate",dict_key_animate)
	e.set_attribute(dict_name,"attenuation",dict_key_attenuation)
	end

end

### ---- set default spotlight values if not present --- ####

def SU2KT::set_default_spotlight(e,dist)

	dict_name="su2kt"

	if !e.attribute_dictionary dict_name
		if e.attribute_dictionary "su2pov"
			dict_key_name = e.get_attribute("su2pov", "name")
			dict_key_power = e.get_attribute("su2pov", "power")
			dict_key_status = e.get_attribute("su2pov", "status")
			dict_key_radius = e.get_attribute("su2pov", "radius")
			dict_key_falloff = e.get_attribute("su2pov", "falloff")
		else #default values
		dict_key_name = "Spotlight"
		dict_key_power = "5"
		dict_key_power = "%.1f" % (1*dist*dist) if dist
		dict_key_status = "On"
		dict_key_radius = "0"
		dict_key_falloff = "100"
		dict_key_dist = dist
		end
	dict_key_animate = " "
	dict_key_attenuation = "Inverse Square"
	e.attribute_dictionary(dict_name, true)
	e.set_attribute(dict_name,"name",dict_key_name)
	e.set_attribute(dict_name,"power",dict_key_power)
	e.set_attribute(dict_name,"status",dict_key_status)
	e.set_attribute(dict_name,"radius",dict_key_radius)
	e.set_attribute(dict_name,"falloff",dict_key_falloff)
	e.set_attribute(dict_name,"animate",dict_key_animate)
	e.set_attribute(dict_name,"distance",dict_key_dist)
	e.set_attribute(dict_name,"attenuation",dict_key_attenuation)
	end

end

# ---- Check light state & intensity in specified animation frame ---- ###

def SU2KT::check_animate_state(animate)

	steps=animate.split('-')
	steps.length.times do |i|
		steps[i]=steps[i].split("[")
		steps[i][1].delete!"]" if steps[i][1]
	end

	timer=@frame/@frame_per_sec.to_f
	i=-1
	while (steps.length-1)>i and timer>steps[i][0].to_f
		timer-=steps[i][0].to_f
		i=i+1
	end

	if @frame/@frame_per_sec.to_f>=steps[0][0].to_f
		ret=steps[i][1]
	else
		ret="DEF"
	end

return ret
end

# -------------------------------- Export Phisical Sky and other settings

def SU2KT::write_sky ( out )
si = Sketchup.active_model.shadow_info
if SU2KT.enable_sun
background="Physical Sky"
else
background="Background Color"
end

	si = Sketchup.active_model.shadow_info
	v = si["SunDirection"]

	point = Geom::Point3d.new 0,0,0
	xvector = Geom::Vector3d.new 1,0,0
	yvector = Geom::Vector3d.new 0,1,0
	zvector = Geom::Vector3d.new 0,0,1
	nangle = si["NorthAngle"].degrees
	tr = Geom::Transformation.rotation point, zvector, -nangle
	tr2 = Geom::Transformation.rotation point, zvector, nangle
	ptx=xvector.transform! tr
	pty=yvector.transform! tr
	v=v.transform! tr2		#Sun direction has to be rotated in opposite direction..

	result=SU2KT.geo_location(false)
	lati=result[0]
	longi=result[1]
	tzoffset=result[2]
	date=result[3]
	time=result[4]

out.puts "<Object Identifier=\"Default Global Settings\" Label=\"Default Global Settings\" Name=\"\" Type=\"Global Settings\">"
out.puts "	<Parameter Name=\"Ambient Light\" Type=\"RGB\" Value=\"0 0 0\"/>"

out.puts "	<Parameter Name=\"Background Color\" Type=\"RGB\" Value=\"0 0 0\"/>"

out.puts "	<Parameter Name=\"Compute Volume Transfer\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"Transfer Recursion Depth\" Type=\"Integer\" Value=\"1\"/>"

out.puts "	<Parameter Name=\"Background Type\" Type=\"String\" Value=\"" + SU2KT.normalize_text(background) + "\"/>"
out.puts "	<Parameter Name=\"Sky Intensity\" Type=\"Real\" Value=\"1\"/>"

out.puts "	<Parameter Name=\"Sky Frame\" Type=\"Transform\" Value=\""+"%.4f"%(ptx.x)+" "+"%.4f"%(pty.x)+" 0 0 "+"%.4f"%(ptx.y)+" "+ "%.4f" % (pty.y) + " 0 0 " + "%.4f" % (ptx.z) + " " + "%.4f" % (pty.z) + " 1 0\"/>"

out.puts "	<Parameter Name=\"Sun Direction\" Type=\"String\" Value=\""+ "%.4f" % (v.x) + " " + "%.4f" % (v.y) + " " + "%.4f" % (v.z) + "\"/>"
out.puts "	<Parameter Name=\"Sky Turbidity\" Type=\"Real\" Value=\"2\"/>"
out.puts "	<Parameter Name=\"./Location/Latitude\" Type=\"Real\" Value=\""+ "%.4f" % (lati) + "\"/>"
out.puts "	<Parameter Name=\"./Location/Longitude\" Type=\"Real\" Value=\"" + "%.4f" % (longi) + "\"/>"
out.puts "	<Parameter Name=\"./Location/Timezone\" Type=\"Integer\" Value=\"" + "%.0f" % (tzoffset) + "\"/>"
out.puts "	<Parameter Name=\"./Location/Date\" Type=\"String\" Value=\"#{date}\"/>"
out.puts "	<Parameter Name=\"./Location/Time\" Type=\"String\" Value=\"#{time}\"/>"
out.puts "</Object>"

end


# ----------------------------------- Export sun possition
def SU2KT::write_sun(out)

	@sunexport=""

	if SU2KT.enable_sun==true
		enabled="1"
	else
		enabled="0"
	end

	sun_power ="3.0" # KT won't calculate it when opening the file, it has to be harcoded
	sun_col = "1 1 1"

	si = Sketchup.active_model.shadow_info
	v = si["SunDirection"]

	boundbox=Sketchup.active_model.bounds
	wsp= boundbox.center
	factor = 50
	pos = wsp.offset(v,[boundbox.max.x,boundbox.max.y,boundbox.max.z].max * factor)

	x=pos.x
	y=pos.y
	z=pos.z

	out.puts "<Object Identifier=\"./Lights/Sun\" Label=\"Default Light\" Name=\"Sun\" Type=\"Light\">"
	out.puts "<Object Identifier=\"Omni Light\" Label=\"Omni Light\" Name=\"\" Type=\"Emittance\">"
	out.puts "<Object Identifier=\"./Radiance/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "<Parameter Name=\"Color\" Type=\"RGB\" Value=\"" + sun_col + "\" />"
	out.puts "</Object>"
	out.puts "<Parameter Name=\"Attenuation\" Type=\"String\" Value=\"None\"/>"
	out.puts "</Object>"
	out.puts "<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"" + enabled + "\"/>"
	out.puts "<Parameter Name=\"Shadow\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Soft Shadow\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "<Parameter Name=\"Negative Light\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "<Parameter Name=\"Global Photons\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Caustic Photons\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Multiplier\" Type=\"Real\" Value=\"" + sun_power.to_s + "\"/>"
	out.puts "<Parameter Name=\"Frame\" Type=\"Transform\" Value=\"1 0 0 #{x.to_m.to_s} 0 1 0 #{y.to_m.to_s} 0 0 1 #{z.to_m.to_s}\"/>"
	out.puts "<Parameter Name=\"Focus Distance\" Type=\"Real\" Value=\"4\"/>"
	out.puts "<Parameter Name=\"Radius\" Type=\"Real\" Value=\"0.2\"/>"
	out.puts "<Parameter Name=\"Shadow Color\" Type=\"RGB\" Value=\"0 0 0\"/>"
	out.puts "</Object>"

	if enabled=="1"
		enabled="ON"
	else
		enabled="OFF"
	end

	@sunexport="Sun & Phisical Sky exported and turned " + enabled +".           \n"
	@lights = []
end

#### Sun related methods

def SU2KT::geo_location(script)

	si = Sketchup.active_model.shadow_info
	location = si["City"]
	country = si["Country"]

	lati= si["Latitude"]
	longi= si["Longitude"]

	tzoffset = si["TZOffset"]
	tzoffset = 0 if tzoffset.abs>12

	date = si["ShadowTime"].utc #Thanks Wehby
	sec = date.sec
	min = date.min

	if date.isdst==true # DaySavingTime
		hour = date.hour-1
		else
		hour = date.hour
	end

	day = date.day
	month = date.month
	if script != true
		month-=1 #Zero indexed month in KT
		day-=1 #Zero indexed day in KT
	end
	time_now=Time.now
	year = time_now.year

	return [lati,longi,tzoffset,"#{day}-#{month}-#{year}","#{hour}:#{min}:#{sec}"] if script == true
	return [lati,longi,tzoffset,"#{day}/#{month}/#{year}","#{hour}:#{min}:#{sec}"] if script != true

end

def SU2KT::generate_sun(out)
	result=SU2KT.geo_location(true)
	lati=result[0]
	longi=result[1]
	tzoffset=result[2]
	date=result[3]
	time=result[4]

	out.puts "message \"./Scenes/#{SU2KT.normalize_text(@model_name)}/GenerateSun #{longi} #{lati} GT#{tzoffset.to_i} #{date} #{time}\""

end

def SU2KT::enable_sun
	@lights==[] or (@lights!=[] and Sketchup.active_model.shadow_info["DisplayShadows"])
end

#### -------------- Export rendering settings ----------------- ##########

def SU2KT::export_global_settings(out)

out.puts "<Root Label=\"Default Kernel\" Name=\"\" Type=\"Kernel\">"
out.puts "<Object Identifier=\"./Modellers/XML Modeller\" Label=\"XML Modeller\" Name=\"XML Modeller\" Type=\"Modeller\">"
out.puts "</Object>"

out.puts "<Object Identifier=\"./Ray Tracers/Standard Ray Tracer\" Label=\"Standard Ray Tracer\" Name=\"Standard Ray Tracer\" Type=\"Ray Tracer\">"
out.puts "	<Parameter Name=\"Rasterization\" Type=\"String\" Value=\"Auto\"/>"
out.puts "	<Parameter Name=\"Antialiasing\" Type=\"String\" Value=\"Production AA\"/>"
out.puts "	<Parameter Name=\"Antialiasing Filter\" Type=\"String\" Value=\"Mitchell-Netravali 0.5 0.8\"/>"
out.puts "	<Parameter Name=\"Antialiasing Threshold\" Type=\"Real\" Value=\"0.3\"/>"
out.puts "	<Parameter Name=\"Texture Filtering\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Brightness Threshold\" Type=\"Real\" Value=\"0.001\"/>"
out.puts "	<Parameter Name=\"Max Ray Tracing Depth\" Type=\"Integer\" Value=\"5\"/>"
out.puts "	<Parameter Name=\"Irradiance Scale\" Type=\"RGB\" Value=\"1 1 1\"/>"
out.puts "	<Parameter Name=\"Linear Lightflow\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Diffuse Samples\" Type=\"Integer\" Value=\"64\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Specular Samples\" Type=\"Integer\" Value=\"8\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Dispersion Samples\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Diffusers\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Translucencies\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Fuzzy Reflections\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Fuzzy Refractions\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Reflections\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Refractions\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Random Generator\" Type=\"String\" Value=\"Pure\"/>"
out.puts "</Object>"
out.puts "<Object Identifier=\"./Irradiance Estimators/Diffuse Interreflection\" Label=\"Diffuse Interreflection\" Name=\"Diffuse Interreflection\" Type=\"Irradiance Estimator\">"
out.puts "	<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Max Recursion Depth\" Type=\"Integer\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Max Ray Tracing Depth\" Type=\"Integer\" Value=\"5\"/>"
out.puts "	<Parameter Name=\"Final Gathering Rays\" Type=\"Integer\" Value=\"500\"/>"
out.puts "	<Parameter Name=\"Light Sampling\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Ambient Lighting\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"Accuracy\" Type=\"Real\" Value=\"0.25\"/>"
out.puts "	<Parameter Name=\"Minimum Pixel Reuse\" Type=\"Real\" Value=\"2.5\"/>"
out.puts "	<Parameter Name=\"Maximum Pixel Reuse\" Type=\"Real\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"Radiance Limit\" Type=\"Real\" Value=\"0.3\"/>"
out.puts "	<Parameter Name=\"Secondary Estimator\" Type=\"String\" Value=\"Density Estimation\"/>"
out.puts "</Object>"
out.puts "<Object Identifier=\"./Irradiance Estimators/Density Estimation\" Label=\"Density Estimation\" Name=\"Density Estimation\" Type=\"Irradiance Estimator\">"
out.puts "	<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Direct Lighting\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Max Photon Tracing Depth\" Type=\"Integer\" Value=\"6\"/>"
out.puts "	<Parameter Name=\"Terminating Brightness\" Type=\"Real\" Value=\"0.01\"/>"
out.puts "	<Parameter Name=\"Samples per Light\" Type=\"Integer\" Value=\"100000\"/>"
out.puts "	<Parameter Name=\"Sample Sky\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Diffuse Samples\" Type=\"Integer\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Specular Samples\" Type=\"Integer\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Dispersion Samples\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Reflections\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Trace Refractions\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Importance Sampling\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"./Sampling Criteria/Russian Roulette\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "</Object>"
out.puts "<Object Identifier=\"./Direct Light Estimators/Refraction Enhanced\" Label=\"Refraction Enhanced\" Name=\"Refraction Enhanced\" Type=\"Direct Light Estimator\">"
out.puts "	<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"PseudoCaustics\" Type=\"Boolean\" Value=\"0\"/>"
out.puts "	<Parameter Name=\"Antialiasing\" Type=\"String\" Value=\"Low\"/>"
out.puts "	<Parameter Name=\"Optimized Area Lights\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "</Object>"
out.puts "<Object Identifier=\"./Environments/Octree Environment\" Label=\"Octree Environment\" Name=\"Octree Environment\" Type=\"Environment\">"
out.puts "	<Parameter Name=\"Max Objects per Cell\" Type=\"Integer\" Value=\"20\"/>"
out.puts "</Object>"
out.puts "<Object Identifier=\"./Filters/Simple Tone Mapping\" Label=\"Simple Tone Mapping\" Name=\"\" Type=\"Filter\">"
out.puts "	<Parameter Name=\"Enabled\" Type=\"Boolean\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Method\" Type=\"String\" Value=\"Simple\"/>"
out.puts "	<Parameter Name=\"Exposure\" Type=\"Real\" Value=\"1\"/>"
out.puts "	<Parameter Name=\"Gamma Correction\" Type=\"Real\" Value=\"2.2\"/>"
out.puts "</Object>"

out.puts "<Object Identifier=\"./Scenes/#{SU2KT.normalize_text(@model_name)}\" Label=\"Default Scene\" Name=\"#{SU2KT.normalize_text(@model_name)}\" Type=\"Scene\">"

end

def SU2KT::finish_close(out)

	out.puts "<Parameter Name=\"./Cameras/Active\" Type=\"String\" Value=\"\#\# Current View \#\#\"/>"
	out.puts "</Object>" #Close scene
	out.puts "</Root>"
	out.close

end

### - Instanced export --- ###

def SU2KT::export_instanced(out,entity_list)
	@mat_sep="_mat:"
	SU2KT.status_bar("SU2KT - Collecting Components")
	SU2KT.collect_components(entity_list, Geom::Transformation.new)
	SU2KT.write_definitions(out)
	SU2KT.status_bar("SU2KT - Writing Components")
	SU2KT.write_packets(out)
	SU2KT.collect_faces(entity_list, Geom::Transformation.new)
	SU2KT.export_faces(out)
	SU2KT.export_fm_faces(out)
end

def SU2KT::collect_components(entity_list,trans)

	for e in entity_list
		if e.class == Sketchup::Group and e.layer.visible? and e.visible?
			SU2KT.push_parent(e)
			SU2KT.collect_components(e.entities, trans*e.transformation)
			@parent_mat.pop
		end

		if (e.class == Sketchup::ComponentInstance and e.layer.visible? and e.visible? and !e.definition.name.include? "_pointlight" and !e.definition.name.include? "_spotlight")
			mat=(e.material==nil) ? @parent_mat.last : e.material
			SU2KT.store_textured_entities(e,mat,true) if (mat.respond_to?(:texture) and mat.texture!=nil)
			comp_def=e.definition
			dict=comp_def.attribute_dictionary "su2kt"
			proxy=dict["high_poly"] if dict!=nil
			comp_def=Sketchup.active_model.definitions[proxy] if proxy!=nil
			proxy=nil
			#if defined?(GhostComp)
			#	if e.definition.get_attribute("__GhostComp__", "__Type__") == "Ghost"
			#		comp_def=GhostComp::GhostCompAlgo.main_from_ghost(e.definition)
			#	end
			#end
			comp_def_name=comp_def.name
			(comp_def_name+=@mat_sep+mat.name) if mat != nil
			(@components[comp_def_name] ||= []) << trans*e.transformation
			SU2KT.push_parent(e)
			SU2KT.collect_components(comp_def.entities, trans*e.transformation)
			@parent_mat.pop
		end
	end
end

def SU2KT::push_parent(e)
	if e.material != nil
		@parent_mat.push(e.material)
	else
		@parent_mat.push(@parent_mat.last)
	end
end

def SU2KT::write_definitions(out)

	@components.each do |comp_def,comp_data|
		out.puts "<Object Identifier=\"./Instances/Model/#{SU2KT.normalize_text(comp_def)}\" Label=\"Default Model\" Name=\"#{SU2KT.normalize_text(comp_def)}\" Type=\"Model\">"
		@parent_mat=[Sketchup.active_model.materials[comp_def.split(@mat_sep).last]]
		SU2KT.export_meshes(out,Sketchup.active_model.definitions[comp_def.split(@mat_sep).first])
		@parent_mat=[]

		out.puts "</Object>"
	end
end

def SU2KT::write_packets(out)
	@components.each do|comp_def, comp_transs|
	out.puts "<Object Identifier=\"./Models/#{comp_def}\" Label=\"Model Package\" Name=\"#{SU2KT.normalize_text(comp_def)}\" Type=\"Model\">"
	out.puts "<Parameter Name=\"Alias\" Type=\"String\" Value=\"#{SU2KT.normalize_text(comp_def)}\"/>"
	out.puts "<Parameter Name=\"Position\" Type=\"Transform List\" Value=\"#{comp_transs.length.to_i}\">"
		comp_transs.each {|trans| out.puts "<T r=\"#{SU2KT.get_kt_matrix(trans)}\"/>"}
	out.puts "</Parameter>"
	out.puts "</Object>"
	end
end

def SU2KT::get_kt_matrix(trans)
	pos=trans.origin
	t=trans.to_a
	vecX=Geom::Vector3d.new t[0],t[1],t[2]
	vecY=Geom::Vector3d.new t[4],t[5],t[6]
	vecZ=Geom::Vector3d.new t[8],t[9],t[10]
	kttrans="%.6f" % (vecX.x)+" "+"%.6f" % (vecY.x)+" "+"%.6f" % (vecZ.x)+" "+"%.6f" % (pos.x*@scale)+" "
	kttrans+="%.6f" % (vecX.y)+" "+"%.6f" % (vecY.y)+" "+"%.6f" % (vecZ.y)+" "+"%.6f" % (pos.y*@scale)+" "
	kttrans+="%.6f" % (vecX.z)+" "+"%.6f" % (vecY.z)+" "+"%.6f" % (vecZ.z)+" "+"%.6f" % (pos.z*@scale)
end

#### Proxy objects creation ####

def SU2KT::create_porxy(su_comp)
	model = Sketchup.active_model
	original_name=su_comp.definition.name
	original_definition=su_comp.definition
	if !original_name.include?("_HIGHPOLY") and model.definitions[original_name+"_HIGHPOLY"]==nil
		model.start_operation "SU2KT - Create proxy"
		su_comp.definition.name=original_name+"_HIGHPOLY"
		new_definition=model.definitions.add original_name
		new_definition.set_attribute("su2kt","high_poly",su_comp.definition.name)

		@edges=[]
		@lengths=[0]
		SU2KT.find_few_edges(original_definition.entities,Geom::Transformation.new)
		entities=new_definition.entities
		@edges.each {|edge| entities.add_edges edge}
		SU2KT.replace_component(su_comp.definition,new_definition,model.entities)
		new_comp=model.entities.add_instance original_definition,su_comp.transformation
		new_comp.hidden=true
		@edges=nil
		@lengths=nil
		model.commit_operation
	else
		UI.messagebox "PROXY ALREADY EXISTS"
	end
end

def SU2KT::restore_high_def(su_comp)
	
end

def SU2KT::find_few_edges(ents,trans)
	ents.each do |ent|
		SU2KT.find_few_edges(ent.entities,ent.transformation*trans) if ent.kind_of?(Sketchup::Group)
		SU2KT.find_few_edges(ent.definition.entities,ent.transformation*trans) if ent.kind_of?(Sketchup::ComponentInstance)
		if ent.kind_of?(Sketchup::Edge) and ent.length>=@lengths.min
			point0=ent.vertices[0].position.transform trans
			point1=ent.vertices[1].position.transform trans
			@edges.push([point0,point1])
			@lengths.push ent.length
			@edges.shift if @edges.length>100
			@lengths.shift if @lengths.length>20
		end
	end
end

def SU2KT::replace_component(old_defin,new_defin,entity_list)
	for e in entity_list
		SU2KT.replace_component(old_defin,new_defin,e.entities) if e.class == Sketchup::Group
		if e.class == Sketchup::ComponentInstance
			if e.definition==old_defin
				e.definition=new_defin
			else
				SU2KT.replace_component(old_defin,new_defin,e.definition.entities)
			end
		end
	end
end

#### -------- Mesh export ---------- ######

def SU2KT::export_meshes(out,ents)

	@parent_mat=[] if @instanced==false

	if @export_meshes==true

		SU2KT.collect_faces(ents, Geom::Transformation.new)
		@current_mat_step = 1
		SU2KT.export_faces(out)
		SU2KT.export_fm_faces(out)

	end
end

###########

def SU2KT::export_faces(out)
	@materials.each{|mat,value|
		if (value!=nil and value!=[])
			SU2KT.export_face(out,mat,false)
			@materials[mat]=nil
		end}
	@materials={}

end

###########

def SU2KT::export_fm_faces(out)
	@fm_materials.each{|mat,value|
		if (value!=nil and value!=[])
			SU2KT.export_face(out,mat,true)
			@fm_materials[mat]=nil
		end}
	@fm_materials={}
end

##### ------------ Collecting entities into an array -------------- ##########

def SU2KT::collect_faces(object, trans)

	if object.class == Sketchup::ComponentInstance
		entity_list=object.definition.entities
	elsif object.class == Sketchup::Group
		entity_list=object.entities
	elsif (object.class == Sketchup::ComponentDefinition and @instanced==true)
		entity_list=object.entities
	elsif object.class == Sketchup::ComponentDefinition
		return
	else
		entity_list=object
	end

	text=""
	text="Component: " + object.definition.name if object.class == Sketchup::ComponentInstance
	text="Group" if object.class == Sketchup::Group

	SU2KT.status_bar("Collecting Faces - Level #{@parent_mat.size} - #{text}")

	for e in entity_list

		if (e.class == Sketchup::Group and e.layer.visible? and e.visible?)
			SU2KT.get_inside(e,trans,false) #e,trans,false - not FM component
		end

		if (e.class == Sketchup::ComponentInstance and @instanced==false and e.layer.visible? and e.visible? and !e.definition.name.include? "_pointlight" and !e.definition.name.include? "_spotlight")
			SU2KT.get_inside(e,trans,e.definition.behavior.always_face_camera?) # e,trans, fm_component?
		end

		if (e.class == Sketchup::Face and e.layer.visible? and e.visible?)

		mat, uvHelp, mat_dir = SU2KT.find_face_material(e)

		if @fm_comp.last==true
			(@fm_materials[mat] ||= []) << [e,trans,uvHelp,mat_dir]
		else
			(@materials[mat] ||= []) << [e,trans,uvHelp,mat_dir] if (@animation==false or (@animation and @export_full_frame))
		end
		@count_faces+=1

		end

	end #for loop

end #method end

def SU2KT::get_inside(e,trans,face_me)
		@fm_comp.push(@fm_comp.last==false ? face_me : true)
		if e.material != nil
			mat = e.material
			@parent_mat.push(e.material)
			SU2KT.store_textured_entities(e,mat,true) if (mat.respond_to?(:texture) and mat.texture!=nil)
		else
			@parent_mat.push(@parent_mat.last)
		end
		SU2KT.collect_faces(e, trans*e.transformation)
		@parent_mat.pop
	@fm_comp.pop
end

def SU2KT::find_face_material(e)
	mat=FRONTF
	uvHelp=nil
	mat_dir=true
	if e.material!=nil
		mat=e.material
	else
		if e.back_material!=nil
			mat=e.back_material
			mat_dir=false
		else
			mat=@parent_mat.last if @parent_mat.last!=nil
		end
	end

	if (mat.respond_to?(:texture) and mat.texture !=nil)
		mat, uvHelp =SU2KT.store_textured_entities(e,mat,mat_dir)
	end

	return [mat,uvHelp,mat_dir]
end


def SU2KT::store_textured_entities(e,mat,mat_dir)

	verb=false

	tw=@texture_writer

	puts "MATERIAL: " + mat.display_name if verb==true
	uvHelp=nil
	number=0
	mat_name=mat.display_name.delete"<>[]"

	if (e.class==Sketchup::Group or e.class==Sketchup::ComponentInstance) and mat.respond_to?(:texture) and mat.texture!=nil
			txcount=tw.count
			handle=tw.load e
			tname=get_texture_name(mat_name,mat)
			@model_textures[mat_name]=[0,e,mat_dir,handle,tname,mat] if (txcount!=tw.count and @model_textures[mat_name]==nil)
			puts "GROUP #{mat_name} H:#{handle}\n#{@model_textures[mat_name]}" if verb==true
	end

	if e.class==Sketchup::Face

		if  @exp_distorted==false
			handle = tw.load(e,mat_dir)
			tname=SU2KT.get_texture_name(mat_name,mat)
			@model_textures[mat_name]=[0,e,mat_dir,handle,tname,mat] if @model_textures[mat_name]==nil
			return [mat_name,uvHelp,mat_dir]
		else

			distorted=SU2KT.texture_distorted?(e,mat,mat_dir)

			txcount=tw.count
			handle = tw.load(e,mat_dir)
			tname=SU2KT.get_texture_name(mat_name,mat)

			if txcount!=tw.count #if new texture added to tw

				if @model_textures[mat_name]==nil
					if distorted==true
						uvHelp=SU2KT.get_UVHelp(e,mat_dir)
						puts "FIRST DISTORTED FACE #{mat_name} #{handle} #{e}" if verb==true
					else
						unHelp=nil
						puts "FIRST FACE #{mat_name} #{handle} #{e}" if verb==true
					end
					@model_textures[mat_name]=[0,e,mat_dir,handle,tname,mat]
				else
					ret=SU2KT.add_new_texture(mat_name,e,mat,handle,mat_dir)
					mat_name=ret[0]
					uvHelp=ret[1]
					puts "DISTORTED FACE #{mat_name} #{handle} #{e}" if verb==true
				end
			else
				@model_textures.each{|key, value|
					if handle==value[3]
						mat_name=key
						uvHelp=SU2KT.get_UVHelp(e,mat_dir) if distorted==true
						puts "OLD MAT FACE #{key} #{handle} #{e} #{uvHelp}" if verb==true
					end}
			end
		end
	end
	puts "FINAL: #{[mat_name,uvHelp,mat_dir].to_s}" if verb==true
	return [mat_name,uvHelp,mat_dir]
end

def SU2KT::add_new_texture(mat_name,e,mat,handle,mat_dir)
	state=@model_textures[mat_name]
	number=state[0]=state[0]+1
	mat_name=mat_name+number.to_s
	tname=SU2KT.get_texture_name(mat_name,mat)
	uvHelp=SU2KT.get_UVHelp(e,mat_dir)
	@model_textures[mat_name]=[number,e,mat_dir,handle,tname,mat]
return [mat_name,uvHelp]
end

def SU2KT::get_texture_name(name,mat)
	ext=mat.texture.filename
	ext=ext[(ext.length-4)..ext.length]
	ext=".png" if (ext.upcase ==".BMP" or ext.upcase ==".GIF" or ext.upcase ==".PNG") #Texture writer converts BMP,GIF to PNG
	ext=".tif" if ext.upcase=="TIFF"
	ext=".jpg" if ext.upcase[0].ord!=46 # 46 = dot
	s=name+ext
	s=@textures_prefix+@model_name+@ds+s
end

def SU2KT::texture_distorted?(e,mat,mat_dir)

	distorted=false
	temp_tw=Sketchup.create_texture_writer
	model = Sketchup.active_model
	entities = model.active_entities
	model.start_operation "Group" #For Undo
	group=entities.add_group
	group.material = mat
	g_handle=temp_tw.load(group)
	temp_handle=temp_tw.load(e,mat_dir)
	entities.erase_entities group
	Sketchup.undo
	distorted=true if temp_handle!=g_handle
	temp_tw=nil
	return distorted

end

def SU2KT::get_UVHelp(e,mat_dir)
	uvHelp = e.get_UVHelper(mat_dir, !mat_dir, @texture_writer)
end

def SU2KT::write_textures

	if (@copy_textures == true and @model_textures!={})

		if FileTest.exist? (@path_textures+@ds+@textures_prefix+@model_name)
		else
			Dir.mkdir(@path_textures+@ds+@textures_prefix+@model_name)
		end

		tw=@texture_writer
		number=@model_textures.length
		count=1
		@model_textures.each do |key, value|
			SU2KT.status_bar("Exporting texture "+count.to_s+"/"+number.to_s)
			if value[1].class== Sketchup::Face
				tw.write value[1], value[2], (@path_textures+@ds+value[4])
			else
				tw.write value[1], (@path_textures+@ds+value[4])
			end
			#TODO: convert png
			ext = @path_textures+@ds+value[4]
			ext=ext[(ext.length-4)..ext.length]
			if (ext.upcase ==".BMP" or ext.upcase ==".GIF" or ext.upcase ==".PNG")
				SU2KT.status_bar("START Exporting texture "+@path_textures+@ds+value[4])
				image = ChunkyPNG::Image.from_file(@path_textures+@ds+value[4])
				image.save(@path_textures+@ds+value[4], :fast_rgba)
				SU2KT.status_bar("STOP Exporting texture "+@path_textures+@ds+value[4])
			end
			# END TODO convert
			count+=1
		end

		status='ok' #TODO

		if status
		stext = "SU2KT: " + (count-1).to_s + " textures and model"
		else
			stext = "An error occured when exporting textures. Model"
		end
		@texture_writer=nil if !@animation
		@model_textures=nil if !@animation
	else
		stext = "Model"
	end

	return stext

end

###########

def SU2KT::point_to_vector(p)
	Geom::Vector3d.new(p.x,p.y,p.z)
end

##### ---- Exporting faces converted to polymeshes ---- #######

def SU2KT::export_face(out,mat,fm_mat)

	meshes = []
	polycount = 0
	pointcount = 0
	mirrored=[]
	mat_dir=[]
	default_mat=[]
	distorted_uv=[]
	if fm_mat
		export=@fm_materials[mat]
	else
		export=@materials[mat]
	end

	has_texture = false
	if mat.respond_to?(:name)
		matname = mat.display_name.delete"<>[]"
		has_texture = true if mat.texture!=nil
	else
		matname = mat
		has_texture=true if matname!=FRONTF
	end

	matname="FM_"+matname if fm_mat


	#Introduced by SJ
	total_mat = @materials.length + @fm_materials.length
	mat_step = " [" + @current_mat_step.to_s + "/" + total_mat.to_s + "]"
	@current_mat_step += 1

	total_step = 4
	if (has_texture and @clay==false) or @exp_default_uvs==true
		total_step += 1
	end
	current_step = 1
	rest = export.length*total_step
	SU2KT.status_bar("Converting Faces to Meshes: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " #{rest}")
	#####


	for face_data in export

		#SU2KT.status_bar("Converting Faces to Meshes: " + matname + " #{@count_faces}") if (@count_faces/200.0==@count_faces/200)
		SU2KT.status_bar("Converting Faces to Meshes: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " #{rest}") if (rest%500==0)
		rest -= 1

		face, trans, uvHelp , face_mat_dir = face_data

		polymesh=((face_mat_dir==true) ? face.mesh(5) : face.mesh(6) )
		trans_inverse = trans.inverse
		default_mat.push(face_mat_dir ? face.material==nil : face.back_material==nil)
		distorted_uv.push(uvHelp)
		mat_dir.push(face_mat_dir)

		polymesh.transform! trans

		xa = SU2KT.point_to_vector(trans.xaxis)
		ya = SU2KT.point_to_vector(trans.yaxis)
		za = SU2KT.point_to_vector(trans.zaxis)
		xy = xa.cross(ya)
		xz = xa.cross(za)
		yz = ya.cross(za)

		mirrored_tmp = true

		if xy.dot(za) < 0
			mirrored_tmp = !mirrored_tmp
		end
		if xz.dot(ya) < 0
			mirrored_tmp = !mirrored_tmp
		end
		if yz.dot(xa) < 0
			mirrored_tmp = !mirrored_tmp
		end
		mirrored << mirrored_tmp

		meshes << polymesh
		@count_faces-=1

		polycount=polycount + polymesh.count_polygons
		pointcount=pointcount + polymesh.count_points
	end

	startindex = 0

# Exporting vertices
	current_step += 1

	out.puts "<Object Identifier=\"./Models/#{SU2KT.normalize_text(matname)}\" Label=\"Default Model\" Name=\"#{SU2KT.normalize_text(matname)}\" Type=\"Model\">"
	out.puts "	<Object Identifier=\"Triangular Mesh\" Label=\"Triangular Mesh\" Name=\"\" Type=\"Surface\">"
	out.puts "	<Parameter Name=\"Vertex List\" Type=\"Point3D List\" Value=\"#{pointcount}\">"

	SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - Verticles " + " #{rest}")

	for mesh in meshes
		SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - Verticles " + " #{rest}") if rest%500==0
		rest -= 1

		for p in (1..mesh.count_points)
			pos = mesh.point_at(p)
			out.print "	<P xyz=\"#{"%.4f" %(pos.x*@scale)} #{"%.4f" %(pos.y*@scale)} #{"%.4f" %(pos.z*@scale)}\"/>\n"
		end
	end
	out.puts "	</Parameter>"

# Exporting normals
	current_step += 1
	i=0
	out.puts "	<Parameter Name=\"Normal List\" Type=\"Point3D List\" Value=\"#{pointcount}\">"
	SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - Normals " + " #{rest}")

	for mesh in meshes
		SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - Normals " + " #{rest}") if rest%500==0
		rest -= 1
		mat_dir_tmp = mat_dir[i]
		mirrored_tmp = mirrored[i]
		for p in (1..mesh.count_points)
			norm = mesh.normal_at(p)
			norm.reverse! if mat_dir_tmp==false
			#norm.reverse! if mirrored_tmp
				out.print "	<P xyz=\"#{"%.8f" %(norm.x)} #{"%.8f" %(norm.y)} #{"%.8f" %(norm.z)}\"/>\n"
		end
		i += 1
	end
out.print "	</Parameter>\n"

# Exporting faces
	current_step += 1
	out.print "	<Parameter Name=\"Index List\" Type=\"Triangle Index List\" Value=\"#{polycount}\">\n"
	i = 0
	startindex = 0
	SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - Faces " + " #{rest}")

	for mesh in meshes
		SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - Faces " + " #{rest}") if rest%500==0
		rest -= 1
		mirrored_tmp = mirrored[i]
		mat_dir_tmp = mat_dir[i]

		for poly in mesh.polygons

			poly.collect! {|point_i| startindex+point_i.abs-1}
			poly.reverse! if mirrored_tmp

			if mat_dir_tmp
				out.print "	<F ijk=\"#{poly[0]} #{poly[1]} #{poly[2]}\"/>\n"
			else
				out.print "	<F ijk=\"#{poly[1]} #{poly[0]} #{poly[2]}\"/>\n"
			end

			@count_tri = @count_tri + 1
		end
		startindex = startindex + mesh.count_points
		i += 1
	end

	out.puts "	</Parameter>"
	out.puts "	<Parameter Name=\"Smooth\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "	<Parameter Name=\"AA Tolerance\" Type=\"Real\" Value=\"15\"/>"
	out.print "	</Object>\n" #Closing Triangular Mesh

# Exporting Material

	if @model_textures[matname]!=nil
		main_mat = @model_textures[matname][5]
	else
		main_mat = mat
	end

	kt_attr=main_mat.attribute_dictionary "su2kt" if main_mat.class!=String

	if (kt_attr!=nil and kt_attr["kt_mat"] !=nil) and @clay==false
		out.puts kt_attr["kt_mat"]
		SU2KT.add_bump(out,mat) if main_mat.respond_to?(:texture) and main_mat.texture!=nil and !kt_attr["kt_mat"].include?("Parameter Name=\"Filename\"")
	else
		if (main_mat.respond_to?(:name) and main_mat.display_name[0..2]=="TG_" and @clay==false)
			SU2KT.export_thin_glass(out,mat)
		else
			SU2KT.export_phong(out,mat,main_mat) if @clay==false
			SU2KT.export_clay(out) if @clay==true
		end
	end

	no_texture_uvs=(!has_texture and @exp_default_uvs==true)
	#Exporting UVs
	if (has_texture and @clay==false) or no_texture_uvs

		out.print "	<Parameter Name=\"Map Channel\" Type=\"Point2D List\" Value=\"#{pointcount}\">\n"

		current_step += 1
		i = 0
		SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - UVs " + " #{rest}")
		for mesh in meshes
			SU2KT.status_bar("Material being exported: " + matname + mat_step + "...[" + current_step.to_s + "/" + total_step.to_s + "]" + " - UVs " + " #{rest}") if rest%500==0
			rest -= 1

			side=(no_texture_uvs) ? true : mat_dir[i]

			for p in (1 .. mesh.count_points)

				if default_mat[i] and @model_textures[matname]!=nil
					inherited_texture=(@model_textures[matname][5]).texture
					texsize = [inherited_texture.width, inherited_texture.height, 1]
				else
					texsize = [1,1,1]
				end

				if distorted_uv[i]!=nil
					uvHelper=(export[i][0]).get_UVHelper(side, !side, @texture_writer)
					point_pos=mesh.point_at(p).transform!(trans.inverse)
					uvs_original=(side ? uvHelper.get_front_UVQ(point_pos) : uvHelper.get_back_UVQ(point_pos))
				else
					uvs_original=mesh.uv_at(p,side)
				end
				uv = [uvs_original.x/texsize.x, uvs_original.y/texsize.y, uvs_original.z/texsize.z]


					out.puts "	<P xy=\"#{"%.4f" %(uv.x)} #{"%.4f" %(-uv.y+1)}\"/>"
			end
			i += 1
		end
		out.puts "	</Parameter>"
	else
		out.puts "	<Parameter Name=\"Map Channel\" Type=\"Point2D List\" Value=\"0\">"
		out.puts "	</Parameter>"
	end

	if (kt_attr != nil and kt_attr["kt_map"] != nil)
		out.puts kt_attr["kt_map"]
	else
		out.puts "	<Parameter Name=\"Frame\" Type=\"Transform\" Value=\"1 0 0 0 0 1 0 0 0 0 1 0\"/>"
		out.puts "	<Parameter Name=\"Visible\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	<Parameter Name=\"Shadow Caster\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	<Parameter Name=\"Shadow Receiver\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	<Parameter Name=\"Caustics Transmitter\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	<Parameter Name=\"Caustics Receiver\" Type=\"Boolean\" Value=\"1\"/>"
	end

	out.puts "</Object>" #Close mesh description
end

##### --- EXPORT THIN GLASS -----#####
def SU2KT::export_thin_glass(out,mat)

	out.puts "<Object Identifier=\"Thin Glass Material\" Label=\"Thin Glass Material\" Name=\"\" Type=\"Material\">"
	if @model_textures[mat]==nil
		material_color=mat.color
		clr=SU2KT.rgb_to_hsb(material_color.red,material_color.green,material_color.blue)
		clr[1]=clr[1]*mat.alpha
		res=hsb_to_rgb(clr[0],clr[1],clr[2])
		out.puts "	<Object Identifier=\"./Reflectance/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
		out.puts "	<Parameter Name=\"Color\" Type=\"RGB\" Value=\"#{res[0]/255.0} #{res[1]/255.0} #{res[2]/255.0}\"/>"
	else
		out.puts "	<Object Identifier=\"./Reflectance/Bitmap Texture\" Label=\"Bitmap Texture\" Name=\"\" Type=\"Texture\">"
		out.puts "	<Parameter Name=\"Filename\" Type=\"String\" Value=\"#{SU2KT.normalize_text(@model_textures[mat][4])}\"/>"
		projection=SU2KT.override_projection
		out.puts projection
		out.puts "	<Parameter Name=\"Smooth\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	<Parameter Name=\"Inverted\" Type=\"Boolean\" Value=\"0\"/>"
	end
	out.puts "	</Object>"
	out.puts "	<Parameter Name=\"Index of Refraction\" Type=\"Real\" Value=\"1.52\"/>"
	SU2KT.add_clip_map(out,mat) if @model_textures[mat]!=nil
	out.puts "</Object>"
end

##### --- EXPORT PHONG -----#####
def SU2KT::export_phong(out,mat,main_mat)

	lum_reduction = 1

	if (@scene_export == true)
		prefix = ".." + @ds
	else
		prefix = ""
	end

	out.puts "<Object Identifier=\"Whitted Material\" Label=\"Whitted Material\" Name=\"\" Type=\"Material\">"

	if @model_textures[mat]!=nil
	#TEXTURE
		out.puts "	<Object Identifier=\"./Diffuse/Weighted Texture\" Label=\"Weighted Texture\" Name=\"\" Type=\"Texture\">"
		out.puts "		<Object Identifier=\"Bitmap Texture\" Label=\"Bitmap Texture\" Name=\"\" Type=\"Texture\">"
		out.puts "		<Parameter Name=\"Filename\" Type=\"String\" Value=\"#{SU2KT.normalize_text(@model_textures[mat][4])}\"/>"
		out.puts "		<Parameter Name=\"Projection\" Type=\"String\" Value=\"UV\"/>"
		out.puts "		</Object>"
		out.puts "	<Parameter Name=\"Bitmap Texture:Weight\" Type=\"Real\" Value=\"#{lum_reduction}\"/>"
		out.puts "</Object>"
	else
	#OR JUST A COLOR
		out.puts "	<Object Identifier=\"./Diffuse/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
		if main_mat.respond_to?(:name) and main_mat.texture==nil
			clr=SU2KT.rgb_to_hsb(mat.color.red,mat.color.green,mat.color.blue)
			clr[2]=clr[2]*lum_reduction
			result=hsb_to_rgb(clr[0],clr[1],clr[2])
			result=[216,216,216] if @clay==true
			result=[255,255,255] if main_mat.display_name[0..7].upcase=="EMITFAKE"
			out.print "		<Parameter Name=\"Color\" Type=\"RGB\" Value=\"#{result[0]/255.0} #{result[1]/255.0} #{result[2]/255.0}\"/>\n"

		else
			colour = Sketchup.active_model.rendering_options["FaceFrontColor"]
			clr=SU2KT.rgb_to_hsb(colour.red,colour.green,colour.blue)
			clr[2]=clr[2]*lum_reduction
			result=hsb_to_rgb(clr[0],clr[1],clr[2])
			result=[216,216,216] if @clay==true
			out.print "		<Parameter Name=\"Color\" Type=\"RGB\" Value=\"#{result[0]/255.0} #{result[1]/255.0} #{result[2]/255.0}\"/>\n"

		end
		out.puts "</Object>"
	end
	# HERE BEGINS
#	begin
#		if mat.respond_to?(:name)
#			mymsg = "MATERIAL: #{mat.name} MAT_ALPHA: #{mat.alpha.to_s} MAT_COL: #{mat.color.red.to_s}/#{mat.color.green.to_s}/#{mat.color.blue.to_s} MAT_IS_ALPHA: #{mat.use_alpha?.to_s}" unless mat.nil?
#		else
#			mymsg = "MATERIAL: " + mat
#		end
#		if main_mat.respond_to?(:name)
#			mymsg = mymsg + "MAIN_MAT: #{main_mat.name} MAIN_MAT_ALPHA: #{main_mat.alpha.to_s} MAIN_MAT_COL: #{main_mat.color.red.to_s}/#{main_mat.color.green.to_s}/#{main_mat.color.blue.to_s} MAT_IS_ALPHA: #{main_mat.use_alpha?.to_s}"
#		end
#		UI.messagebox mymsg unless mymsg.nil?
#	rescue Exception => e  
#		out.puts e.message  
#		out.puts e.backtrace.inspect  
#	end
	# HERE ENDS
	if (mat.respond_to?(:name) and mat.use_alpha?)
		ior=1
		out.puts "<Object Identifier=\"./Refraction/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
		out.puts "	<Parameter Name=\"Color\" Type=\"RGB\" Value=\"#{1.0-mat.alpha} #{1.0-mat.alpha} #{1.0-mat.alpha}\"/>"
#		UI.messagebox "MAT ALPHA: #{mat.alpha}"
		out.puts "</Object>"
	else
		ior=1
		if (main_mat.respond_to?(:name) and main_mat.use_alpha?)
			out.puts "<Object Identifier=\"./Refraction/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
			out.puts "	<Parameter Name=\"Color\" Type=\"RGB\" Value=\"#{1.0-main_mat.alpha} #{1.0-main_mat.alpha} #{1.0-main_mat.alpha}\"/>"
#			UI.messagebox "MAT ALPHA: #{main_mat.alpha}"
			out.puts "</Object>"		
		end
	end

	if @model_textures[mat]!=nil
		out.print "	<Parameter Name=\"Smooth\" Type=\"Boolean\" Value=\"1\"/>\n"
		out.print "	<Parameter Name=\"Inverted\" Type=\"Boolean\" Value=\"0\"/>\n"
	end

	out.print "	<Parameter Name=\"Shininess\" Type=\"Real\" Value=\"128\"/>\n"
	out.print "	<Parameter Name=\"Transmitted Shininess\" Type=\"Real\" Value=\"128\"/>\n"
	out.print "	<Parameter Name=\"Index of Refraction\" Type=\"Real\" Value=\"#{ior}\"/>\n"
	out.print "	<Parameter Name=\"Specular Sampling\" Type=\"Boolean\" Value=\"0\"/>\n"
	out.print "	<Parameter Name=\"Transmitted Sampling\" Type=\"Boolean\" Value=\"0\"/>\n"
	out.print "	<Parameter Name=\"Specular Attenuation\" Type=\"String\" Value=\"Fresnel\"/>\n"
	out.print "	<Parameter Name=\"Transmitted Attenuation\" Type=\"String\" Value=\"Fresnel\"/>\n"
	out.puts "	</Object>"

	SU2KT.add_clip_map(out,mat) if @model_textures[mat]!=nil

	if mat.respond_to?(:name)
		if mat.display_name.upcase.include? "EMITFAKE"
			SU2KT.add_emitter(out,1.0, mat, false)
		end
		if mat.display_name.upcase.include? "EMIT["
			power=(mat.display_name.split('[')[1]).split(']')[0]
			SU2KT.add_emitter(out,power, mat, true)
		end
	end
end

#### Emitter description ####

def SU2KT::add_emitter(out,power,mat,true_emiter)

	out.puts "<Object Identifier=\"Diffuse Light\" Label=\"Diffuse Light\" Name=\"\" Type=\"Emittance\">"
	out.puts "	<Object Identifier=\"./Radiance/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "	<Parameter Name=\"Color\" Type=\"RGB\" Value=\"#{mat.color.red/255.0} #{mat.color.green/255.0} #{mat.color.blue/255.0}\"/>"
	out.puts "	</Object>"
	out.puts "	<Parameter Name=\"Attenuation\" Type=\"String\" Value=\"Inverse Square\"/>"
	out.puts "	<Parameter Name=\"Emitter\" Type=\"Boolean\" Value=\"#{true_emiter ? 1 : 0}\"/>"
	out.puts "	<Parameter Name=\"Front Side\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "	<Parameter Name=\"Back Side\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "<Parameter Name=\"Power\" Type=\"Real\" Value=\"#{power.to_f}\"/>"
	out.puts "<Parameter Name=\"Efficiency\" Type=\"Real\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Unit\" Type=\"String\" Value=\"Watts/sr/m2\"/>"
	out.puts "</Object>"
end

##### --- EXPORT CLAY MATERIAL -----#####

def SU2KT::export_clay(out)
	out.puts "<Object Identifier=\"Whitted Material\" Label=\"Whitted Material\" Name=\"Clay\" Type=\"Material\">"
	out.puts "	<Object Identifier=\"./Ambient/Null Texture\" Label=\"Null Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "	</Object>"
	out.puts "	<Object Identifier=\"./Diffuse/Constant Texture\" Label=\"Constant Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "	<Parameter Name=\"Color\" Type=\"RGB\" Value=\"0.85 0.85 0.76\"/>"
	out.puts "	</Object>"
	out.puts "	<Parameter Name=\"Shininess\" Type=\"Real\" Value=\"128\"/>"
	out.puts "	<Parameter Name=\"Transmitted Shininess\" Type=\"Real\" Value=\"128\"/>"
	out.puts "	<Parameter Name=\"Index of Refraction\" Type=\"Real\" Value=\"3\"/>"
	out.puts "	<Parameter Name=\"Specular Sampling\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "	<Parameter Name=\"Transmitted Sampling\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "	<Parameter Name=\"Specular Attenuation\" Type=\"String\" Value=\"Fresnel\"/>"
	out.puts "	<Parameter Name=\"Transmitted Attenuation\" Type=\"String\" Value=\"Fresnel\"/>"
	out.puts "</Object>"
end

### Add Bump description ###

def SU2KT::add_bump(out,mat)

	out.puts "<Object Identifier=\"Bump Mapping\" Label=\"Bump Mapping\" Name=\"\" Type=\"Intersection Modifier\">"
	out.puts "<Object Identifier=\"./Texture/Weighted Texture\" Label=\"Weighted Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "<Object Identifier=\"Bitmap Texture\" Label=\"Bitmap Texture\" Name=\"\" Type=\"Texture\">"
	out.puts "<Parameter Name=\"Filename\" Type=\"String\" Value=\"#{SU2KT.normalize_text(@model_textures[mat][4])}\"/>"
	projection=SU2KT.override_projection
	out.puts projection
	out.puts "<Parameter Name=\"Smooth\" Type=\"Boolean\" Value=\"1\"/>"
	out.puts "<Parameter Name=\"Inverted\" Type=\"Boolean\" Value=\"0\"/>"
	out.puts "</Object>"
	out.puts "<Parameter Name=\"Bitmap Texture:Weight\" Type=\"Real\" Value=\"1\"/>"
	out.puts "</Object>"
	out.puts "<Parameter Name=\"Strength\" Type=\"Real\" Value=\"5\"/>"
	out.puts "</Object>"

end

### Clip mapping

def SU2KT::add_clip_map(out,mat)
	ext=(@model_textures[mat][4]).split('.').last.upcase
	if (ext=="PNG" or ext=="TIF")
		out.puts "<Object Identifier=\"Alpha Mapping\" Label=\"Alpha Mapping\" Name=\"\" Type=\"Acceptance Modifier\">"
		out.puts "	<Object Identifier=\"./Texture/Bitmap Texture\" Label=\"Bitmap Texture\" Name=\"\" Type=\"Texture\">"
		out.puts "	<Parameter Name=\"Filename\" Type=\"String\" Value=\"#{@model_textures[mat][4]}\"/>"
		out.puts SU2KT.override_projection
		out.puts "	<Parameter Name=\"Smooth\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	<Parameter Name=\"Inverted\" Type=\"Boolean\" Value=\"0\"/>"
		out.puts "	<Parameter Name=\"Alpha Channel\" Type=\"Boolean\" Value=\"1\"/>"
		out.puts "	</Object>"
		out.puts "<Parameter Name=\"Threshold\" Type=\"Real\" Value=\"0.5\"/>"
		out.puts "</Object>"
	end
end

#### -- IMPORT KT MATERIAL FROM LIBRARY --- ###

def SU2KT::import_kt_material
	SU2KT.reset_global_variables
	materials=SU2KT.collect_kt_materials
	return if materials==nil
	selection=Sketchup.active_model.selection
	su_mats=SU2KT.selection_2_SU_mats(selection) if selection.length!=0
	return if selection.length!=0 and su_mats==nil
	kt_mats=SU2KT.select_material(materials)
	return if kt_mats==nil

	if Sketchup.active_model.materials.length != 0
		if selection.length==0
			number=SU2KT.assign_or_create(kt_mats)
		else
			number=SU2KT.assign_kt_mat(kt_mats,@su_materials)
			@su_materials=nil
			number=[0,number]
		end
	else
		number=SU2KT.add_materials(kt_mats,nil)
		number=[number,0]
	end

	text="#{number[0]} material added.\n#{number[1]} material(s) attached." 
	UI.messagebox (text)
end

def SU2KT::collect_kt_materials #Collect libraries and material names
	path=SU2KT.get_kt_path
	return if path==nil
	path=File.join(path.split(@ds))
	path=File.dirname(path)+"/MaterialEditor/Libraries/*/*.names"
	files=Dir[path]
	folders=[]
	files.each do |file|
		file_body=File.new(file,"r")
		content=[]
		while (line = file_body.gets)
			content.push line.chomp
		end
		file_body.close
		folders.push([File.basename(file,".names"),content])
	end
	folders
end

def SU2KT::select_material(folders) #Select materials to be imported
	folders.reverse!
	dialog_limit=12
	i=0
	prom=[]
	drop=[]
	val=[]
	folders.each do |lib_name,lib_mat_names|
		prom.push lib_name
		drop.push (["-None-",lib_mat_names,"-All-"].join("|"))
		val.push "-None-"
	end
	results=SU2KT.display_dialog(prom,drop,val,"Import KT Materials")
	return nil if results==nil
	path=SU2KT.get_kt_path
	path=File.join(path.split(@ds))
	path=File.dirname(path)+"/MaterialEditor/Libraries/"
	kt_mats=[]
	i=0
	folders.each do |lib_name,lib_mat_names|
			kt_mats.push([path+"#{lib_name}/#{lib_name}.xml",results[i]]) if lib_mat_names.include? results[i]
			if results[i]=="-All-"
				lib_mat_names.each do |mat|
					kt_mats.push([path+"#{lib_name}/#{lib_name}.xml",mat])
				end
			end
			i+=1
	end
	kt_mats
end

def SU2KT::assign_or_create(kt_mats)
	prom=[]
	drop=[]
	val=[]
	kt_mats.each do |lib_path, lib_mat_name|
		prom.push lib_mat_name
		drop.push ["Create new","Attach to existing  "].join("|")
		val.push "Create new"
	end
	results=SU2KT.display_dialog(prom,drop,val,"Create New or Attach to Existing SU Material")
	assign_me=[]
	create_me=[]
	(kt_mats.length).times do |i|
		if results[i]=="Create new"
			create_me.push kt_mats[i]
		else
			assign_me.push kt_mats[i]
		end
	end
		su_mats=[]
		model=Sketchup.active_model
		model.materials.each {|mat| su_mats.push mat.display_name}
		su_mats.sort!
	assigned=0
	assigned=SU2KT.assign_kt_mat(assign_me,su_mats) if assign_me!=[]
	created=SU2KT.add_materials(create_me,nil) if create_me!=[]
	return [created,assigned]
end

def SU2KT::assign_kt_mat(kt_mats,su_mats)
	return nil if su_mats==[]
	model=Sketchup.active_model
	prom=[]
	drop=[]
	val=[]
	kt_mats.each do |lib_path, lib_mat_name|
		prom.push lib_mat_name
		drop.push((["-None-"]+su_mats).join("|"))
		val.push "-None-"
	end
	results=SU2KT.display_dialog(prom,drop,val,"Attach KT material to:")
	return if results==nil
	number=0
	model.start_operation("KT Materials attach")
	results.length.times do |i|
		if results[i]!="-None-" and results[i]!=nil
			added=SU2KT.add_materials([kt_mats[i]],model.materials[results[i]])
			number+=1 if added != 0
		end
	end
	model.commit_operation
	number
end

def SU2KT::add_materials(kt_mats,mat) #Attach KT materials to SU mats
	return 0 if kt_mats==[]
	model=Sketchup.active_model

	model.start_operation("Create KT Mat")

	update=(mat!=nil)
	materials=model.materials
	number=0
	kt_mats.each do |kt_lib_path,kt_name|

		kt_lib_path=SU2KT.check_library(kt_lib_path)

		if kt_lib_path != nil

			kt_data=SU2KT.load_material(kt_lib_path,kt_name) #Get mat description from the library

			mat_content,map_content,color,textures,kt_alpha = kt_data

			if (kt_data==nil or mat_content==nil or map_content==nil)
				SU2KT.mat_import_error(kt_mat)
				return number
			end

			mat=materials.add kt_name if update==false
			mat.set_attribute("su2kt","kt_lib_path",kt_lib_path)
			mat.set_attribute("su2kt","kt_name",kt_name)

			mat.set_attribute("su2kt","kt_mat",mat_content)
			mat.set_attribute("su2kt","kt_map",map_content)

			#mat.color=[255,0,174] if update==false #color if color!=[]
			if textures !=[]
				default_size=60
				default_size=mat.texture.height if mat.texture!=nil
				tex=textures.rassoc "DIFF"
				if tex != nil
					mat.texture=tex[0]
				else
					mat.texture=textures.first.first
				end
				mat.texture.size=default_size
			else
				mat.texture = nil
			end

			if color.length != 0
				mat.color=[color[0],color[1],color[2]]
			end

			if kt_alpha.length != 0
				alpha = 1.0 - kt_alpha[0].to_f/255.0
				if alpha < 0.2
					alpha = 0.2
				end
				mat.alpha=alpha
			elsif !mat.texture
				mat.alpha=1.0
			end

			number+=1
		end
	end
	model.commit_operation
	return number
end

def SU2KT::mat_import_error(kt_mat)
	UI.messagebox("SU2KT couldn't import \"#{kt_mat}\" material.\nPlease report it at KT Forum in Sketchup section\nhttp://www.kerkythea.net", MB_MULTILINE , "SU2KT - Material Import Error")
end

def SU2KT::load_material(file,kt_mat) #Extracr material from the KT library with given path
	file_body=File.new(file,"r")
	first_line=SU2KT.find_mat_line(file_body,kt_mat)
	if first_line==nil
		SU2KT.mat_import_error(kt_mat)
		return nil
	end
	kt_data=SU2KT.extract_kt_material(file_body,first_line)
	file_body.close
	kt_data
end

def SU2KT::find_mat_line(file_body,kt_mat_name)
	while line = file_body.gets
			return line if (line.include?"Name=\"#{kt_mat_name}\"" and line.include?"Type=\"Material\"")
			return line if kt_mat_name=="Sky Portal" and line.include?"Object Identifier=\"Sky Portal Light\""
	end
	return nil
end

def SU2KT::extract_kt_material(file_body,first_line)

	kt_data=[]
	content_mat=[]
	content_mat.push first_line
	content_map=[]
	color=[]
	alpha=[]
	textures=[]
	map_param=false
	object=2 # Def Model & Mat
	objectIdentifier = []

	mixColor = false
	mixAlpha = false

	while object!=0
		line = file_body.gets

		if line[0..6]=="<Object"
			object+=1
			objectIdentifier.push getXMLValue("Identifier", line)
			currentObject = objectIdentifier.last
		end
		if line[0..8]=="</Object>"
			object-=1
			objectIdentifier.pop
			currentObject = objectIdentifier.last
		end

		tex_type=SU2KT.texture_type(line) if tex_type==nil

		if currentObject
			if currentObject.include?("Diffuse")
				mixColor = setColor(color, mixColor, line)
			elsif currentObject.include?("Refraction")
				mixColor = setColor(color, mixColor, line)
			elsif currentObject.include?("Ambient")
				mixColor = setColor(color, mixColor, line)
			elsif currentObject.include?("Reflection")
				mixColor = setColor(color, mixColor, line)
				mixAlpha = setAlpha(alpha, mixColor, line, color)
			elsif currentObject.include?("Reflectance")
				mixColor = setColor(color, mixColor, line)
				mixAlpha = setAlpha(alpha, mixColor, line, color)
			end
		end

		if line.include? "Parameter Name=\"Filename\""
			line_split=line.split "\""
			file_name=File.basename(line_split[-2])
			file_name=File.dirname(file_body.path)+"/"+file_name
			line_split[-2]=file_name
			line=line_split.join("\"")
			textures.push [file_name,tex_type]
			tex_type=nil
		end
		if line.include? "Parameter Name=\"Projection\" Type=\"String\""
			5.times {file_body.gets}
			content_mat.push SU2KT.override_projection
			line=file_body.gets
		end
		if line.include? "Parameter Name=\"Map Channel\""
			file_body.gets #Omit also next line
			map_param=true
		else
			content_mat.push line if map_param==false and object!=0
			content_map.push line if map_param==true and object!=0
		end
	end

	return [content_mat.join(""),content_map.join(""),color,textures,alpha] #Some idiots are amending array .to_s method!! 

end

####>>>>>    Introduced by JS

def SU2KT::getXMLValue(name, line)
	i = line.index(name)
	if i != nil
		iS = line.index('"', i) + 1
		iE = line.index('"', iS) - 1
		iL = iE - iS + 1
		return line[iS,iL]
	end
	return ""
end

def SU2KT::setColor(color, mixColor, line)
	if getXMLValue("Name", line) == "Color" && getXMLValue("Type", line) == "RGB"
		rgba = getXMLValue("Value", line)
		rgba = rgba.split(" ")
		i = 0
		rgba.each{|value|
			if mixColor
				color[i] = (((value.to_f * 255.0).to_i + color[i])/2).to_i
			else
				color << (value.to_f * 255.0).to_i
			end
			i += 1
		}
		#UI.messagebox "Color: " + getXMLValue("Value", line) + "\r\nColor: " + color[0].to_s + ", " + color[1].to_s + ", " + color[2].to_s
		return true
	end 
	return false
end

def SU2KT::setAlpha(alpha, mixAlpha, line, color)
	if getXMLValue("Name", line) == "Color" && getXMLValue("Type", line) == "RGB"
		rgba = getXMLValue("Value", line)
		#UI.messagebox "alpha: " + rgba
		rgba = rgba.split(" ")
		alph = 0
		rgba.each{|value|
			tmp = (value.to_f * 255).to_i
			if tmp > alph
				alph = tmp
			end
		}
		if mixAlpha
			alpha[0] = ((alph + color[0])/2).to_i
		else
			alpha << alph
		end
		return true
	end 
	return false
end

#### ^^^^^^^^^^^^^^  Introduced by JS

def SU2KT::texture_type(line)
	tex_type=nil
	tex_type="DIFF" if line.include? "Object Identifier=\"./Diffuse"
	tex_type="BUMP" if line.include? "Object Identifier=\"Bump Mapping"
	tex_type="SPEC" if line.include? "Object Identifier=\"./Specular"
	tex_type="REFL" if line.include? "Object Identifier=\"./Reflection"
	tex_type="REFR" if line.include? "Object Identifier=\"./Refraction"
	tex_type="LUMI" if line.include? "Object Identifier=\"./Radiance"
	return tex_type
end

def SU2KT::override_projection
	def_projection="<Parameter Name=\"Projection\" Type=\"String\" Value=\"UV\"/>\n<Parameter Name=\"Offset X\" Type=\"Real\" Value=\"0\"/>\n"
	def_projection+="<Parameter Name=\"Offset Y\" Type=\"Real\" Value=\"0\"/>\n<Parameter Name=\"Scale X\" Type=\"Real\" Value=\"1\"/>\n"
	def_projection+="<Parameter Name=\"Scale Y\" Type=\"Real\" Value=\"1\"/>\n<Parameter Name=\"Rotation\" Type=\"Real\" Value=\"0\"/>\n"
end

def SU2KT::check_library(file) #if exists
	return file if FileTest.exist? file
	path=SU2KT.get_kt_path
	return nil if path==nil
	path=File.join(path.split(@ds))
	path=File.dirname(path)+"/MaterialEditor/Libraries/"
	file=path+File.join(file.split("/")[-2..-1])
	if FileTest.exist? file
		return file
	else
		UI.messagebox("SU2KT couldn't find \"#{kt_name}\" material.\nin the following file:\n#{file}", MB_MULTILINE , "SU2KT - Material Import Error")
		return nil
	end
end

def SU2KT::selection_2_SU_mats(selection)
	SU2KT.status_bar("Collecting SU materials from Selection")
	@su_materials=[]
	SU2KT.collect_SU_materials(selection)
	SU2KT.status_bar("")
	SU2KT.status_bar("No material to attach KT material found.") if @su_materials==[] 
	return nil if @su_materials==[] 
	@su_materials.uniq! if @su_materials.length>1
	@su_materials.sort!
end

def SU2KT::collect_SU_materials(selection)
	for e in selection
		if e.class == Sketchup::Group and e.layer.visible? and e.visible?
			@su_materials.push e.material.display_name if e.material!=nil
			SU2KT.collect_SU_materials(e.entities)
		end
		if e.class == Sketchup::ComponentInstance and e.layer.visible? and e.visible?
			SU2KT.collect_SU_materials(e.definition.entities)
			@su_materials.push e.material.display_name if e.material!=nil
		end
		if e.class==Sketchup::Face
			@su_materials.push e.material.display_name if e.material!=nil
			@su_materials.push e.back_material.display_name if e.back_material!=nil#@su_materials.push e.back_material.display_name
		end
	end
end

### KT Materiels manager ###

def SU2KT::kt_mats_manager
	SU2KT.reset_global_variables
	mats=SU2KT.find_kt_mats
	if mats!=[]
		results=SU2KT.select_kt_dict(mats)
	else
		UI.messagebox "No KT materials imported\\attached yet."
	end
	SU2KT.edit_mats(mats,results) if results!=nil
end

def SU2KT::find_kt_mats
	mats=Sketchup.active_model.materials
	edit_pack=[]
	mats.each {|mat| edit_pack.push mat if (mat.attribute_dictionary "su2kt")}
	edit_pack
end

def SU2KT::select_kt_dict(mats)

	installed_mats=SU2KT.collect_kt_materials
	prom=[]
	drop=[]
	val=[]
	mats.each do |mat|
	dict=mat.attribute_dictionary "su2kt"
	prom.push mat.display_name
	libname=dict["kt_lib_path"].split("/")[-2]
	kt_mat=libname+" \\ #{dict["kt_name"]}" #Lib_name\kt_mat_name

	if SU2KT.is_installed(libname,dict["kt_name"],installed_mats)
		drop.push (["- Detach KT material", kt_mat ,"< Update"].join("|"))
	else
		drop.push (["- Detach KT material", kt_mat].join("|"))
	end
	val.push(kt_mat)
	end
	results=SU2KT.display_dialog(prom,drop,val,"KT Materials Update\\Detach")
end

def SU2KT.is_installed(lib_name,kt_name,installed)
	found=false
	installed.each do |ilib,names|
		names.each {|name| found=true if name==kt_name} if ilib==lib_name
	end
	return found
end


def SU2KT::edit_mats(mats,results)

	assign_me=[]
	updated=0
	detached=0
	mats.length.times do |i|
		if results[i]=="- Detach KT material"
			mats[i].delete_attribute "su2kt" 
			detached+=1
		elsif results[i]=="< Update"
			dict=mats[i].attribute_dictionary "su2kt"
			updated+=SU2KT.add_materials([[dict["kt_lib_path"],dict["kt_name"]]],mats[i])
		end
	end
	UI.messagebox "#{updated} material(s) updated.\n"+(detached ==0 ? "No material detached" : "#{detached} material(s) detached.")
end

def SU2KT::display_dialog(prompts,dropdowns,values,wind_name)
	dialog_limit=12
	i=0
	results=[]
	prom=[]
	drop=[]
	val=[]
	len=prompts.length.to_i
	while prompts.length>0
	prom.push prompts.shift
	drop.push dropdowns.shift
	val.push values.shift
	i+=1
		if (i/dialog_limit)!=((i-1)/dialog_limit) or i==len
			number=(len/dialog_limit.to_f).ceil
			res = inputbox(prom,val,drop,wind_name+" - #{(i/dialog_limit.to_f).ceil} of #{number}")
			return nil if res==false
			prom.clear
			drop.clear
			val.clear
			results+=res
		end
	end
	results
end

#### - Send text to status bar - ####
def SU2KT::status_bar(stat_text)
	statbar = Sketchup.set_status_text(@status_prefix + stat_text)
end

def SU2KT::normalize_text(s)
	stmp = s.gsub( "&", "&amp;" )
	stmp = stmp.gsub( "<", "&lt;" )
	stmp = stmp.gsub( ">", "&gt;" )
	stmp = stmp.gsub( "\"", "&quot;" )
	stmp = stmp.gsub( "'", "&apos;" )
end

# ===================================================================
# === New methods ===================================================
# ===================================================================

##### ------ Select scene render settings ------ #####
# Returns [resolution, render setting XML filename]
# or nil if the dialog window is cancelled
def SU2KT::render_settings_window

	files = []
	values = []   # Default values for inputbox
	resolution = %w[Model-Inherited 320x240 640x480 768x576 800x600].join("|")

	settings, files=SU2KT.get_render_settings # Render setting names  , Render setting filenames (with full path)

	# Build the rendering options inputbox
	prompts = ["Resolution", "Render Setting"]
	stored_values = SU2KT.get_stored_values # [5] = resolution, [6] = render setting
	values[0] = stored_values[5]
	if File.exist?(stored_values[6]) # Does the stored file still exist?
		values[1] = File.basename(stored_values[6], ".xml")
	else
		values[1] = settings[0] # Use the first render setting file that was found
	end
	dropdowns = [resolution, settings.join("|")]

	results = UI.inputbox(prompts, values, dropdowns, "Scene export rendering options")
	return nil if not results

	stored_values[5] = results[0] # resolution
	stored_values[6] = files[settings.index(results[1])] # render setting
	SU2KT.store_values(stored_values)

	return [stored_values[5], stored_values[6]]

end


def SU2KT::get_render_settings
	settings = [] # Render settings (just the render setting name)
	# Build a list of render settings from the Plugins/SU2KT directory
	path = File.dirname(__FILE__) + "/su2kt/*.xml"
	files = Dir[path]

	# Build a list of render settings from the Kerkythea directory
	path = SU2KT.get_kt_path
	return nil if (path == nil)
	path = File.join(path.split(@ds)) # convert separator to "/"
	path = File.dirname(path) + "/RenderSettings/*.xml"
	files += Dir[path]

	# Strip off directory and file extension
	files.each {|file| settings.push(File.basename(file, ".xml"))}
	return [settings, files]
end

##### ------ Select script path ------ #####
# Asks the user to select the script file directory and filename
# Sets @model_name = <model> filename
#      @frames_path        = full path of the Anim_<model> directory
# Returns the full path of the <model>.kst script file
# or nil if the dialog window is cancelled
def SU2KT::select_script_path_window

	model = Sketchup.active_model
	model_filename = File.basename(model.path)
	if model_filename != ""
		name=(model_filename.split(".")[0 .. -2]).to_s
		model_name = name + ".kst"
	else
		model_name = "Untitled.kst"
	end
	script_file = UI.savepanel("Export Script Path", "", model_name)
	return nil if (script_file == nil)

	if script_file==script_file.split(".")[0 .. -2].to_s # No file extension
		script_file += ".kst"
	end
	@model_name=File.basename(script_file)
	@model_name=@model_name.split(".")[0]

	@frames_path=File.dirname(script_file)+@ds+"Anim_"+File.basename(script_file).split(".")[0 .. -2].to_s
	if not FileTest.exist?(@frames_path)
		Dir.mkdir(@frames_path)
	end

	return script_file
	
end

##### ------ Export render settings ------ #####
# Copies the render settings file into the model file
# out           = output file
# settings_file = render settings XML file
def SU2KT::export_render_settings(out, settings_file)

	out.puts "<Root Label=\"Default Kernel\" Name=\"\" Type=\"Kernel\">"

	# Remove the root delimiters from the settings file
	IO.foreach(settings_file) do |line|
		temp = line.lstrip.downcase # Lower case, remove leading whitespace
		if (temp.index('<root') != 0 and temp.index('</root') != 0)
			out.puts(line)
		end
	end

	out.puts "<Object Identifier=\"./Scenes/#{SU2KT.normalize_text(@model_name)}\" Label=\"Default Scene\" Name=\"#{SU2KT.normalize_text(@model_name)}\" Type=\"Scene\">"

end

##### ------ Report on export scene results ------ #####
# Displays the output path and statistics from the scene export
# Derived from SU2KT::report_window
# start_time  = time the export operation started
# stext       = prefix for status bar text
# script_file = full path of the .kst script file
# Returns UI.messagebox result (6 = "Yes")
def SU2KT::scene_report_window(start_time, stext, script_file)

	end_time=Time.new
	elapsed=end_time-start_time
	time=" exported in "
	(time=time+"#{(elapsed/3600).floor}h ";elapsed-=(elapsed/3600).floor*3600) if (elapsed/3600).floor>0
	(time=time+"#{(elapsed/60).floor}m ";elapsed-=(elapsed/60).floor*60) if (elapsed/60).floor>0
	time=time+"#{elapsed.round}s. "

	SU2KT.status_bar(stext+time+" Triangles = #{@count_tri}")
	export_text = "Scene models saved in directory:\n" + @frames_path
	export_text += "\n\nAnimation script saved in file:\n" + script_file

	UI.messagebox(export_text + "\n\nCameras exported: " + @n_cameras.to_s + "\n" + @sunexport + "Lights exported:\nPointlights: " + @n_pointlights.to_s +  "   Spotlights: " + @n_spotlights.to_s+"\n\nRender exported scene animation in Kerkythea?",MB_YESNO)

end

##### ------ Export scenes ------ #####
def SU2KT::export_scene

	SU2KT.reset_global_variables

	model = Sketchup.active_model
	if model.pages.count == 0 # No scenes
		SU2KT.status_bar("No scenes to export.\nUsing Export Model function instead.")
		SU2KT.export
		return
	end

	return if (SU2KT.export_options_window == false)

	render_settings = SU2KT.render_settings_window
	return if (render_settings == nil)

	script_file = SU2KT.select_script_path_window
	return if (script_file == nil)

	@scene_export = true
	@resolution = render_settings[0]
	@path_textures = File.dirname(script_file)

	start_time = Time.new
	stext = ""
	scene_number = 0
	scene_format = "%0" + model.pages.count.to_s.length.to_s + "d"
	original_scene = model.pages.selected_page # Save the current scene

	script = File.new(script_file, "w")

	model.pages.each do |scene|
		# Skip scenes that are hidden - label starts "(" and ends ")"
		next if (scene.label[0] == 40 and scene.label[-1] == 41)

		scene_number += 1
		model.pages.selected_page = scene
		scene_file = (scene_format % scene_number) + ".xml"
		@export_file = @frames_path + @ds + scene_file

		script.puts("message \"Load #{@export_file}\"")
		script.puts("message \"Render\"")
		script.puts("message \"SaveImage " + @frames_path + @ds + (scene_format % scene_number) + ".jpg\"")

		@status_prefix = "Scene " + scene_number.to_s + ": "
		out = File.new(@export_file,"w")

		SU2KT.export_render_settings(out, render_settings[1])

		entity_list=model.entities
		SU2KT.find_lights(entity_list,Geom::Transformation.new)

		SU2KT.write_sky(out)
		SU2KT.export_meshes(out,entity_list)
		SU2KT.export_current_view(model.active_view, out)
		@n_cameras=1

		SU2KT.export_lights(out) if @export_lights==true
		SU2KT.write_sun(out)
		SU2KT.finish_close(out)

	end # model.pages.each do

	script.close # Close the script file
	model.pages.selected_page = original_scene # Return to original scene
	@status_prefix = "" # Finished with scene related operations
	stext=SU2KT.write_textures
	result=SU2KT.scene_report_window(start_time, stext, script_file)
	@export_file = script_file # Used by render_animation as the script path
	SU2KT.render_animation if result==6

	SU2KT.reset_global_variables

end


### END OF Tim's new methods

### ------ Function RGB_2_HSB -------- ###
def SU2KT::rgb_to_hsb(r, g, b)

	r/=255.0
	g/=255.0
	b/=255.0

	rgb_max = [r,g,b].max
	rgb_min = [r,g,b].min

	v = rgb_max.to_f

	if rgb_max != 0
		s = (rgb_max - rgb_min).to_f / (rgb_max).to_f
	else
		s = 0.0
		h = 0.0
		return h,s,v*100.0
	end

	if r==g && g==b
		h=0
	else
		h = ( g-b )/ (rgb_max - rgb_min).to_f if r == rgb_max
		h = 2.0 + (b-r).to_f/(rgb_max - rgb_min).to_f if g == rgb_max
		h = 4.0 + (r-g).to_f/(rgb_max - rgb_min).to_f if b == rgb_max
	end

	h+=6 if h<0
	return ((h*600.0).round)/10.0,((s*1000.0).round)/10.0,((v*1000.0).round)/10.0
end

### ------ Function HSB_2_RGB -------- ###

def SU2KT::hsb_to_rgb(h,s,v)

	if ((s == 0) && (h == 0))
		r = g = b = v
	end
	v/=100.0
	s/=100.0
	h = 0.0 if (h == 360)

	h /= 60.0
	i = h.floor
	f = h - i
	p = v*(1 - s)
	q = v*(1 - s*f)
	t = v*(1 - s*(1 - f))

	case i
	when 0
		r = v
		g = t
		b = p
	when 1
		r = q
		g = v
		b = p
	when 2
		r = p
		g = v
		b = t
	when 3
		r = p
		g = q
		b = v
	when 4
		r = t
		g = p
		b = v
	when 5
		r = v
		g = p
		b = q
	end

	r*=255.0
	g*=255.0
	b*=255.0

	return r.round,g.round,b.round
end

##### -----  FaceMe Components export ------- ######

def SU2KT::export_faceme

	@current_mat_step = 1
	SU2KT.reset_global_variables

	model = Sketchup.active_model
	pages = model.pages

	model_filename = File.basename(model.path)
	if model_filename!=""
		model_name = "FM_"+model_filename.split(".")[0].to_s
		model_name += ".xml"
	else
		model_name = "Untitled_FaceMe.xml"
	end

	@export_file=UI.savepanel("Export FaceMe Components & Sun", "" , model_name)

	return if @export_file==nil

	@model_name=File.basename(@export_file)
	@model_name=model_name.split(".")[0].to_s

	if @export_file==@export_file.split(".")[0].to_s
		@export_file+=".xml"
	end

	out = File.new(@export_file,"w")

		SU2KT.export_global_settings(out)

		SU2KT.write_sky(out)
		SU2KT.export_current_view(model.active_view, out)
		SU2KT.write_sun(out)

		SU2KT.collect_faces(Sketchup.active_model.entities, Geom::Transformation.new)
		SU2KT.export_fm_faces(out)

		SU2KT.finish_close(out)

	UI.messagebox "Face Me Components saved into   \n\n#{@export_file}\n"

end

##### -----  Animation export ------- ######

def SU2KT::animation

	SU2KT.reset_global_variables
	@animation=true
	@textures_prefix = ".."+@ds+ @textures_prefix

	model = Sketchup.active_model
	pages = model.pages
	@frame=0

	@frame_per_sec = %w[30 25 23.98 20 15 10 5 1].join("|")
	loop_cam = %w[Yes No].join("|")
	@anim_sun = %w[Yes No].join("|")
	face_me = %w[Yes No].join("|")
	full_frame= %w[Yes No].join("|")
	resolution = %w[Model-Inherited 320x240 640x480 768x576 800x600].join("|")
	render_set, rend_files = SU2KT.get_render_settings

	prompts=["Frames per second   ","Loop to first camera  ","Animated Lights and Sun?   ","Face-Me Components?  ","Full model per frame?      ","Resolution  ","Render Settings"]
	dropdowns = [@frame_per_sec,loop_cam,@anim_sun,face_me,full_frame,resolution,render_set.join("|")]
	values = SU2KT.get_stored_values #[6] = render setting

	values[6]=File.exist?(values[6]) ? File.basename(values[6], ".xml") : render_set[0] # If file doesn't exist use the first render setting file that was found

	results = inputbox prompts,values, dropdowns, "Animation export options"
	return nil if not results

	results[6] = rend_files[render_set.index(results[6])] # replace rendering setting with full file path
	SU2KT.store_values(results)

	@frame_per_sec=results[0].to_f

	loop_cam=(results[1]=="Yes")
	@anim_sun=(results[2]=="Yes")
	face_me=(results[3]=="Yes")
	@export_full_frame=(results[4]=="Yes")
	face_me=true if @export_full_frame
	@resolution=(results[5]=="Model-Inherited") ? "4x4" : results[5]

	model_filename = File.basename(model.path)
	if model_filename!=""
		model_name = model_filename.split(".")[0].to_s
		model_name += ".kst"
	else
		model_name = "Untitled_Anim.kst"
	end

	#Export of a Master Frame with rendering settings
	continue=SU2KT.export_options_window 
	return if !continue

	@export_file=UI.savepanel("Export Animation Script", "" , model_name)
	return if @export_file==nil

		master_file=File.dirname(@export_file)+"/"+model_name.split(".").first+".xml"
		out = File.new(master_file,"w")
		@path_textures=File.dirname(master_file)
		model = Sketchup.active_model
		#SU2KT.export_global_settings(out)
		SU2KT.export_render_settings(out, results[6])

		SU2KT.find_lights(model.entities,Geom::Transformation.new)

		SU2KT.write_sky(out)

		SU2KT.export_meshes(out,model.entities) if @instanced==false
		SU2KT.export_instanced(out,model.entities) if @instanced==true

		SU2KT.export_current_view(model.active_view, out)

		SU2KT.export_lights(out) if @export_lights==true
		SU2KT.write_sun(out)
		SU2KT.finish_close(out)
		SU2KT.write_textures

	@model_name=File.basename(@export_file)
	@model_name=model_name.split(".")[0]

	if @export_file==@export_file.split(".")[0]
		@export_file+=".kst"
	end

	@frames_path=File.dirname(@export_file)+@ds+"Anim_"+File.basename(@export_file).split(".")[0]

	(Dir.mkdir(@frames_path)) if !FileTest.exist? (@frames_path)

	time=pages.slideshow_time

	if loop_cam==true
		kt_page=pages.add "SU2KT_Loop"
		transit=[]
		pages.each {|page| transit.push(page.transition_time) if page.label==page.name}
		add_time=transit[0]
		pages.show_frame_at @frame
		kt_page.update
		kt_page.transition_time=add_time
		add_time = Sketchup.active_model.options["PageOptions"]["TransitionTime"] if add_time==-1	#default transition time
		time+=add_time
	end

	model_file=@export_file.split(".")[0]+".xml"

	if time > 0

		SU2KT.set_merge_settings

		@out = File.new(@export_file,"w")

		@out.puts "message \"Load #{File.basename(model_file)}\""

		@hold_on=true
		if face_me==true
			su_anim=SU2KTAnim.new
			Sketchup.active_model.active_view.animation = su_anim #Start animation of the camera
			while @hold_on==true
				choice=UI.messagebox "Exporting Animation...\nPlease wait and press OK when asked to\n-check status line at the bottom\n", MB_OKCANCEL
				if choice==2
					Sketchup.active_model.active_view.animation = nil
					su_anim.stop
					@out.close
					pages.show_frame_at time
					Sketchup.send_action "pageDelete:" if loop_cam==true
					return
				end
			end

		else #No Face_me option
			while @frame/@frame_per_sec<time
				pages.show_frame_at @frame/@frame_per_sec

				frame_file=File.new("#{@frames_path}"+@ds+SU2KT.add_zeros(@frame)+".xml","w")
				SU2KT.export_global_settings(frame_file)
				SU2KT.write_sky(frame_file)
				if @export_full_frame
					SU2KT.collect_faces(Sketchup.active_model.entities, Geom::Transformation.new)
					SU2KT.export_faces(frame_file)
					SU2KT.export_fm_faces(frame_file)
				end
				SU2KT.export_current_view(model.active_view, frame_file)
				SU2KT.export_lights(frame_file)

				SU2KT.finish_close(frame_file)

				@out.puts "message \"Merge '#{@frames_path}"+@ds+SU2KT.add_zeros(@frame)+".xml' #{@merge_settings}\""
				if @anim_sun==true
					SU2KT.generate_sun (@out)
				end
				@out.puts "message \"Render\""
				@out.puts "message \"SaveImage #{@frames_path}"+@ds+SU2KT.add_zeros(@frame)+".jpg\""

				SU2KT.lock_cache if (@anim_sun==false and @frame==0)

				@frame+=1
			end
		end

		@out.close
		pages.show_frame_at time+0.1
		Sketchup.send_action "pageDelete:" if loop_cam==true

		result=UI.messagebox "Animation script exported and saved into   \n#{@export_file}\n\nAll frames saved in:\n#{@frames_path+@ds}\n\nMaster model saved in: #{master_file}\n\nAnimation duration: #{time} sec.\n\nRender exported animation in Kerkythea?",MB_YESNO

		SU2KT.render_animation if result==6
	else
		UI.messagebox "No pages present."
	end

	Sketchup.active_model.active_view.animation = nil

end

def self.hold_on=(b)
	@hold_on=b
end

def self.get_anim_params
	[@frame_per_sec,@frames_path, @export_full_frame, @out]
end

def SU2KT::lock_cache
	@out.puts "message \"./Irradiance Estimators/Density Estimation/Lock Cache\""
	@out.puts "message \"./Irradiance Estimators/Diffuse Interreflection/Lock Cache\""
end


def SU2KT::set_merge_settings
	@merge_settings="5 " #replace meshes keep materials
	if @anim_sun==true
		@merge_settings+="1 " #replace lights
	else
		@merge_settings+="0 " #keep lights
	end
	if @resolution=="4x4"
		@merge_settings+="5 " #keep camera settings, modify possition
	else
		@merge_settings+="4 " #repalce camera & resolution
	end
	@merge_settings+="0 " #keep render settings
	if @anim_sun==true
		@merge_settings+="1" #replace global settings
	else
		@merge_settings+="0" #keep global settings
	end
end

def self.merge_settings
	@merge_settings
end

def SU2KT::get_stored_values
	model=Sketchup.active_model
	dict_name="su2kt"
	if model.attribute_dictionary dict_name
		anim_fps=model.get_attribute(dict_name, "anim_fps")
		anim_loop=model.get_attribute(dict_name, "anim_loop")
		anim_animsun=model.get_attribute(dict_name, "anim_animsun")
		anim_faceme=model.get_attribute(dict_name, "anim_faceme")
		full_frame=model.get_attribute(dict_name, "anim_full_frame")
		anim_resol=model.get_attribute(dict_name, "anim_resol")
		anim_render=model.get_attribute(dict_name, "anim_render")

		anim_render = "" if (anim_render == nil)# Dictionary was written without the render setting
		full_frame="No" if (full_frame == nil)

		values=[anim_fps, anim_loop, anim_animsun, anim_faceme, full_frame, anim_resol, anim_render]

	else
		model.attribute_dictionary(dict_name, true)
		values=["15","No","No","No","No","640x480",""]
		SU2KT.store_values values
	end
	return values
end

def SU2KT::store_values (values)
	model=Sketchup.active_model
	dict_name="su2kt"
	model.set_attribute(dict_name,"anim_fps",values[0])
	model.set_attribute(dict_name,"anim_loop",values[1])
	model.set_attribute(dict_name,"anim_animsun",values[2])
	model.set_attribute(dict_name,"anim_faceme",values[3])
	model.set_attribute(dict_name,"anim_full_frame",values[4])
	model.set_attribute(dict_name,"anim_resol",values[5])
	model.set_attribute(dict_name,"anim_render",values[6])

end

##### ----- Frames renumbering ----- ####

def SU2KT::add_zeros(frame)

	total_frames=(Sketchup.active_model.pages.slideshow_time/(1.0/@frame_per_sec)).to_i
	str_length=total_frames.to_s.length
	frame_length=frame.to_s.length
	name="0"*(str_length+2)
	name[str_length+1-frame_length..str_length+1]=frame.to_s
	return name

end


# Start insert light tool
def SU2KT::instert_point
	Sketchup.active_model.select_tool SU2KTL.new("su2kt_pointlight.skp")
end

def SU2KT::insert_spot
	Sketchup.active_model.select_tool SU2KTL.new("su2kt_spotlight.skp")
end

#Validation of selection

	def SU2KT::point_selected
		s = Sketchup.active_model.selection
		model=Sketchup.active_model
		ss=model.selection.first
		cName=ss.definition.name if not s.empty? and ss.class == Sketchup::ComponentInstance

		return false if ((s.empty?) || (s.length > 1))
		return ss if (s.first.class == Sketchup::ComponentInstance and cName.include? "su2" and cName.include? "_pointlight")
	end

	def SU2KT::spot_selected
		s = Sketchup.active_model.selection
		model=Sketchup.active_model
		ss=model.selection.first
		cName=ss.definition.name if not s.empty? and ss.class == Sketchup::ComponentInstance

		return false if ((s.empty?) || (s.length > 1))
		return ss if (s.first.class == Sketchup::ComponentInstance and cName.include? "su2" and cName.include? "_spotlight")
	end

	def SU2KT::valid_selection?(sel,proxed)
		return false if ((sel.empty?) || (sel.length > 1))
		return true if proxed == false and sel.first.class == Sketchup::ComponentInstance
		return true if (proxed == true and sel.first.class == Sketchup::ComponentInstance and sel.first.definition.attribute_dictionary("su2kt")!=nil and sel.first.definition.attribute_dictionary("su2kt")["proxy_name"]!=nil)
		false
	end

	def SU2KT::valid_component(proxy)
	end

end #Class end

class SU2KTAnim

def initialize
	@frame=0
	@slide_time=0.0
	@frame_per_sec, @frames_path, @export_full_frame, @out=SU2KT.get_anim_params
	@ds= (ENV['OS'] =~ /windows/i) ? "\\" : "/"

end

def nextFrame(view)
	Sketchup::set_status_text(@frame, 2)

	@slide_time=@frame/@frame_per_sec

	Sketchup.active_model.pages.show_frame_at @slide_time

	@frame_file=File.new("#{@frames_path}"+@ds+SU2KT.add_zeros(@frame)+".xml","w")
		SU2KT.export_global_settings(@frame_file)
		SU2KT.write_sky(@frame_file)
		SU2KT.export_current_view(Sketchup.active_model.active_view, @frame_file)
		SU2KT.export_lights(@frame_file)
		if @export_full_frame==true
			SU2KT.export_meshes(@frame_file, Sketchup.active_model.entities)
		else
			SU2KT.collect_faces(Sketchup.active_model.entities, Geom::Transformation.new)
			SU2KT.export_fm_faces(@frame_file)
		end
		SU2KT.finish_close(@frame_file)

		@out.puts "message \"Merge '#{@frames_path}"+@ds+SU2KT.add_zeros(@frame)+".xml' #{SU2KT.merge_settings}\""
		if @anim_sun==true
			SU2KT.generate_sun (@out)
		end
		@out.puts "message \"Render\""
		@out.puts "message \"SaveImage #{@frames_path}"+@ds+SU2KT.add_zeros(@frame)+".jpg\""

	SU2KT.lock_cache if @anim_sun==false and @frame==0

	@frame+=1
	if @frame/@frame_per_sec >= Sketchup.active_model.pages.slideshow_time
		self.stop
		SU2KT.hold_on=false
		SU2KT.status_bar("Exporting Face Me Components FINISHED. Press OK!")
		return false
	end
	return true
end

def stop
	Sketchup::set_status_text("", 1)
	Sketchup::set_status_text("", 2)
	@frame_file.close if !@frame_file.closed?
end

def fakeExport()

	#Get animation accessor
	sr=SketchyReplay::SketchyReplay.new()

	#Check for animation in the file
	return if (sr.lastFrame==0)

	#set objects pos and camera for first frame.
	sr.start()

	#export first frame here

	0.upto(sr.lastFrame){
		#advance object and camera positions
		sr.nextFrame()
		puts sr.frame
		#export frame here:
	}

	#cleanup
	sr.rewind()

end

end # class AnimCamera

#--------------------------------------- Lights placing tool ----------------------
class SU2KTL

def initialize(comp)
	SU2KT.reset_global_variables
	@ip1 = nil
	@ip1 = nil
	@drawn=false
	@compname=comp
	model=Sketchup.active_model
	status=model.start_operation("Insert Light")
	model.commit_operation
end

def activate
	@ip = Sketchup::InputPoint.new
	@ip1 = Sketchup::InputPoint.new
	@ip2 = Sketchup::InputPoint.new
	SU2KT::status_bar("Select instertion point of the light")
	self.reset(nil)
end

def deactivate(view)
	view.invalidate
end

def onMouseMove(flags, x, y, view)
	if @state==0
		@ip.pick view, x, y
		if( @ip != @ip1 )
			view.invalidate if( @ip.display? or @ip1.display? )
			@ip1.copy! @ip
			view.tooltip = @ip1.tooltip if( @ip1.valid? )
		end
	else
		@ip2.pick view, x, y, @ip1
		view.tooltip = @ip2.tooltip if( @ip2.valid? )
		view.invalidate
	end
end

def onLButtonDown(flags, x, y, view)
	if (@state==0)
		@ip1.pick view, x, y
		if( @ip1.valid? )
			Sketchup::set_status_text "Select pointlight\'s range", SB_PROMPT if (@compname=="su2kt_pointlight.skp")
			Sketchup::set_status_text "Select spotlight\'s target", SB_PROMPT if (@compname=="su2kt_spotlight.skp")
			@state=1
		end
	elsif (@state==1)
		if(@ip2.valid?)
			self.create_light(view)
			self.reset(view)
			@state=0
		end
	end
end

def draw(view)

	if( @ip1.valid? )
		if( @ip1.display? )
			@ip1.draw(view)
			@drawn = true
		end
	end
	if( @ip2.valid? )
		@ip2.draw(view) if( @ip2.display?)
		length = (@ip1.position.distance(@ip2.position)).to_m
		self.draw_geometry(@ip1.position, @ip2.position, view)
		@drawn = true
	end
end

def onCancel(flag, view)
	mod=Sketchup.active_model
	mod.select_tool nil if @state==0
	self.reset(view)
end

def reset(view)
	@state = 0
	SU2KT::status_bar("Select instertion point of the light")
	@ip.clear
	@ip1.clear
	@ip2.clear
	if( view )
		view.tooltip = nil
		view.invalidate
	end
	@drawn = false
end

def draw_geometry(pt1,pt2,view)
	view.set_color_from_line(pt1,pt2)
	view.line_stipple="-.-"
	view.line_width = 1
	view.draw(GL_LINE_STRIP, pt1, pt2)
end

def deactivate(view)
	view.invalidate if @drawn
end

def create_light(view)
	pt1=@ip1.position
	pt2=@ip2.position
	model=Sketchup.active_model
	definitions=model.definitions
	path=Sketchup.find_support_file(@compname,"Plugins/su2kt")
	if path==nil #TO DO - create light if no skp
		UI.messagebox("No \'#{@compname}\' found in Plugins/su2kt folder.\nPlease copy it to SketchUp Plugins folder from\nthe instalation archive or create manually.",MB_OK)
		return
	end
	definition=definitions.load(path.to_s)
	model.start_operation("Insert Light")
	light=model.active_entities.add_instance(definition, @ip1.position)
	vector=pt1 - pt2
	vector2=vector.clone
	vector2.length=1
	pt1=pt1-vector2
	vector2=vector
	vector2=Geom::Vector3d.new(0,0,1) if @compname=="su2kt_pointlight.skp"
	trans=Geom::Transformation.new(pt1,vector2)
	light.transformation=trans
	dist=vector.length.to_m
	SU2KT.set_pointlight_params(light,dist) if @compname=="su2kt_pointlight.skp"
	SU2KT.set_spotlight_params(light,dist) if @compname=="su2kt_spotlight.skp"
	model.commit_operation

end

end # class SU2KT_Light insert

# ---- Menu items and icons ---- #
if( not file_loaded?(__FILE__) )

	main_menu = UI.menu("Plugins").add_submenu("Kerkythea Exporter")
	main_menu.add_item("Export Model") {SU2KT.export}
	main_menu.add_item("Export Scenes - batch render") {SU2KT.export_scene}
	main_menu.add_separator
	main_menu.add_item("Export Animation Path") {SU2KT.animation}
	main_menu.add_separator
	main_menu.add_item("Export Face Me Components and Sun") {SU2KT.export_faceme}
	main_menu.add_separator
	main_menu.add_item("Import KT materials") {SU2KT.import_kt_material}
	main_menu.add_separator
	main_menu.add_item("KT Materials Update\\Detach") {SU2KT.kt_mats_manager}
	main_menu.add_separator
	main_menu.add_item("About SU2KT") {SU2KT.about}

	UI.add_context_menu_handler do |menu|

	menu.add_separator if ( SU2KT.point_selected ) or (SU2KT.spot_selected)
	menu.add_item("SU2KT: Edit Pointlight") {SU2KT.set_pointlight_params(SU2KT.point_selected,nil)} if SU2KT.point_selected
	menu.add_item("SU2KT: Edit Spotlight") {SU2KT.set_spotlight_params(SU2KT.spot_selected,nil)} if SU2KT.spot_selected
	sel = Sketchup.active_model.selection
	menu.add_item("SU2KT: Replace by proxy object") {SU2KT.create_porxy(sel.first)} if SU2KT.valid_selection?(sel,false)
	if SU2KT.valid_selection?(sel,true)
		menu.add_item("SU2KT: Restore high poly definition") {SU2KT.restore_high_def(sel.first)}
	end

	end

	dir= File.dirname(__FILE__)
	cmd_array = []		# Use an array of commands to make it easier to
						# add, delete, and rearrange items
	cmd = UI::Command.new("Export Model") {SU2KT.export}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_icon.png"
	cmd.status_bar_text = cmd.tooltip = "Export model to Kerkythea"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Export Scenes") {SU2KT.export_scene}
	cmd.large_icon = dir+"/su2kt/kt_scene.png"
	cmd.small_icon = dir+"/su2kt/kt_scene_sm.png"
	cmd.status_bar_text = cmd.tooltip = "Export Scenes to Kerkythea (batch render)"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Export Animation") {SU2KT.animation}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_anim.png"
	cmd.status_bar_text = cmd.tooltip = "Export animation to Kerkythea"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Export FM Components and Sun") {SU2KT.export_faceme}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_faceme.png"
	cmd.status_bar_text = cmd.tooltip = "Export Face Me Components and Sun"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Insert Point Light") {SU2KT.instert_point}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_point.png"
	cmd.status_bar_text = cmd.tooltip = "Insert Point Light"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Insert Spot Light") {SU2KT.insert_spot}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_spot.png"
	cmd.status_bar_text = cmd.tooltip = "Insert Spot Light"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Import KT materials") {SU2KT.import_kt_material}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_mats.png"
	cmd.status_bar_text = cmd.tooltip = "Import KT materials"
	cmd_array.push(cmd)

	cmd = UI::Command.new("Open KT Materials Manager") {SU2KT.kt_mats_manager}
	cmd.large_icon = cmd.small_icon = dir+"/su2kt/kt_manager.png"
	cmd.status_bar_text = cmd.tooltip = "KT Materials Update\\Detach"
	cmd_array.push(cmd)

	tb = UI::Toolbar.new("SU2Kerkythea")
	cmd_array.each {|i| tb.add_item(i)}

	tb.show if tb.get_last_state == -1

end
file_loaded(__FILE__)