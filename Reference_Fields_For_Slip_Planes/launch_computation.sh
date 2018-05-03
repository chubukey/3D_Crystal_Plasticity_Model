#!/bin/bash

## Input material orientation
hkl_list=(0 1 0)
uvw_list=(1 0 0)

## Modify the Input File (for file names)
sed -i -e "s/	hkl =.*/	hkl = np.asarray([ ${hkl_list[0]}, ${hkl_list[1]}, ${hkl_list[2]}])/" Input_Computation.py
sed -i -e "s/	uvw =.*/	uvw = np.asarray([ ${uvw_list[0]}, ${uvw_list[1]}, ${uvw_list[2]}])/" Input_Computation.py

# Transformation from Miller Indices to Zmat orientation
Vectors=$(python <<< "
import numpy as np ;
hkl = [ ${hkl_list[0]}, ${hkl_list[1]}, ${hkl_list[2]}]; 
uvw = [ ${uvw_list[0]}, ${uvw_list[1]}, ${uvw_list[2]}];
hkl = np.asarray(hkl); 
uvw = np.asarray(uvw);
def miller_to_euler(hkl, uvw):	
	qrs = np.cross(hkl, uvw) ;
	Nhkl = np.linalg.norm(hkl) ;
	Nuvw = np.linalg.norm(uvw) ;
	Nqrs = np.linalg.norm(qrs) ;
	g = np.array([[ uvw[0]/Nuvw,  qrs[0]/Nqrs, hkl[0]/Nhkl ],
	                [ uvw[1]/Nuvw, qrs[1]/Nqrs, hkl[1]/Nhkl ],
	                [ uvw[2]/Nuvw, qrs[2]/Nqrs, hkl[2]/Nhkl] ])     ;       
	R = np.array([[1,0,0],[0,0,-1],[0,1,0]]);
        g_prime = np.matmul(g, R )
	if abs(g_prime[2][2]-1)<1e-6 :
	        phi1 = np.arctan(g_prime[0][1]/g_prime[0][0])*180/np.pi ;
	        psi  = 0.;
	        phi2 = 0.;
	else :
	        phi1 = np.arctan(-g_prime[2][0]/g_prime[2][1])*180/np.pi;
	        psi  = np.arccos(g_prime[2][2])*180/np.pi;
	        phi2 = np.arctan(g_prime[0][2]/g_prime[1][2])*180/np.pi;
	print('%f %f %f' % (phi1, psi, phi2));

def miller_to_euler_1(hkl, uvw):	
	h,k,l = hkl;
	u, v, w = uvw;
	Nhkl = np.linalg.norm(hkl) ;
	Nuvw = np.linalg.norm(uvw) ;
	psi = np.arccos(l/Nhkl)*180/np.pi;
	phi2 = np.arccos(k/np.sqrt(h**2+k**2))*180/np.pi;
	phi1 = np.arcsin(w*Nhkl/(Nuvw*np.sqrt(h**2+k**2)))*180/np.pi;
	print('%f %f %f' % (phi1, psi, phi2));

def miller_to_matrix(hkl, uvw):
	qrs = np.cross(hkl, uvw) ;
	Nhkl = np.linalg.norm(hkl) ;
	Nuvw = np.linalg.norm(uvw) ;
	Nqrs = np.linalg.norm(qrs) ;
	g = np.array([[ uvw[0]/Nuvw,  qrs[0]/Nqrs, hkl[0]/Nhkl ],
			[ uvw[1]/Nuvw, qrs[1]/Nqrs, hkl[1]/Nhkl ],
			[ uvw[2]/Nuvw, qrs[2]/Nqrs, hkl[2]/Nhkl] ]) 	;
	R = np.array([[1,0,0],[0,0,-1],[0,1,0]]);
	g_prime = np.matmul(g, R )
	X1 = np.dot( g_prime, np.array([1,0,0]) )	;					
	X2 = np.dot( g_prime, np.array([0,1,0]) )	;
	X1_txt = '%f %f %f' % (X1[0],X1[1],X1[2]) ;
	X2_txt = '%f %f %f' % (X2[0],X2[1],X2[2]) ;
	print( 'x1 %s x2 %s' %(X1_txt, X2_txt) ) ;

miller_to_matrix(hkl, uvw)" )

echo "${Vectors}"

used_material='am1_20'

## Generate INP File
abaqus_6.11-2 cae noGUI=Create_INP_file.py

## Import JobName and sources' path from previous computation

EL_JobName_I=$(sed -n 1p EL_job_details_I.txt).inp
EL_JobName_II=$(sed -n 1p EL_job_details_II.txt).inp
EL_JobName_III=$(sed -n 1p EL_job_details_III.txt).inp

EP_JobName_I=$(sed -n 1p EP_job_details_I.txt).inp
EP_JobName_II=$(sed -n 1p EP_job_details_II.txt).inp
EP_JobName_III=$(sed -n 1p EP_job_details_III.txt).inp
EP_JobName_Mix=$(sed -n 1p EP_job_details_Mix.txt).inp

OdbSrc=$(sed -n 3p EP_job_details_I.txt)
OdbSrcEL=$(sed -n 4p EP_job_details_I.txt)
OdbSrcLGEOM=$(sed -n 5p EP_job_details_I.txt)

## Up-date the material orientation in the Zmat file

material_file_elastic="material_model_elastic_${used_material}.zmat"
sed -i -e "s/rotation.*/rotation ${Vectors}/" ${material_file_elastic}
Zpreload ${material_file_elastic} > "Zpreload_material_model_elastic_${used_material}.txt"

grep -A 4 '*MATERIAL,NAME' "Zpreload_material_model_elastic_${used_material}.txt" > material_def_inp.inp

## Write INP files for pure elastic computation

for JobName in $EL_JobName_I $EL_JobName_II $EL_JobName_III
do
	## Insert the Zmat material configuration in the inp file
	sed -i -e "s/material=Elastic-Plastic\s*$/material=${material_file_elastic}/" $JobName
	sed -i -e "s/material=Elastic\s*$/material=${material_file_elastic}/" $JobName
	#sed -i -e 's/material=Elastic-Rigid\s*$/material=material_model_elastic.zmat/' "$JobName"
	materials_location=`grep -n '** MATERIALS' $JobName | awk -F ":" '{print $1}'`
	insertion_line=$(($materials_location+2))
	sed -i "${insertion_line}i **here" $JobName
	begin="**here"
	end="*Material, name=Elastic-Rigid"
	sed -i -e "/$begin/,/$end/{/$begin/{p; r material_def_inp.inp
		}; /$end/p; d}" $JobName
	sed -i '/**here/d' $JobName
	## Launch Job on Zmat
	# To configurate Zebulon with abaqus_6.11-2
	#source ~zebulon/Z8.7/do_config.sh 
	#Zmat cpus=12 memory=16gb $JobName
done

inp_folder="inp_files_${hkl_list[0]}${hkl_list[1]}${hkl_list[2]}_${uvw_list[0]}${uvw_list[1]}${uvw_list[2]}"
mkdir -p $inp_folder
mv EL_* $inp_folder/
cp ${material_file_elastic} ${inp_folder}/

sed -i -e "s/rotation.*/rotation ${Vectors}/" "material_model_elastic_plastic_${used_material}.zmat"

slip_systems_list=("(1. 1. 1.) (-1. 0. 1.)" "(1. 1. 1.) (0. -1. 1.)" "(1. 1. 1.) (-1. 1. 0.)" "(1. -1. 1.) (-1. 0. 1.)" "(1. -1. 1.) (0. 1. 1.)" "(1. -1. 1.) (1. 1. 0.)" "(-1. 1. 1.) (0. -1. 1.)" "(-1. 1. 1.) (1. 1. 0.)" "(-1. 1. 1.) (1. 0. 1.)" "(1. 1. -1.) (-1. 1. 0.)" "(1. 1. -1.) (1. 0. 1.)" "(1. 1. -1.) (0. 1. 1.)")
slip_systems_suffix=("b4" "b2" "b5" "d4" "d1" "d6" "a2" "a6" "a3" "c5" "c3" "c1")

for (( i=0; i<${#slip_systems_list[@]}; i++ ))
do
	slip_system=${slip_systems_list[$i]}
	slip_suffix=${slip_systems_suffix[$i]}
	material_file_elastic_plastic="material_model_elastic_plastic_${used_material}_${slip_suffix}.zmat"
	cp "material_model_elastic_plastic_${used_material}.zmat" ${material_file_elastic_plastic}
	sed -i -e "s/**potential.*/**potential slip ${slip_system}/" ${material_file_elastic_plastic}
	Zpreload ${material_file_elastic_plastic} > "Zpreload_material_model_elastic_plastic_${used_material}_${slip_suffix}.txt"
	## Write INP files for elastic-plastic computation
	grep -A 4 '*MATERIAL,NAME' "Zpreload_material_model_elastic_${used_material}.txt" > material_def_inp.inp
	grep -A 4 '*MATERIAL,NAME' "Zpreload_material_model_elastic_plastic_${used_material}_${slip_suffix}.txt" >> material_def_inp.inp
	for JobName in $EP_JobName_I $EP_JobName_II $EP_JobName_III $EP_JobName_Mix
	do
		NewJobName="${JobName}_${slip_suffix}"
		cp $JobName $NewJobName
		## Insert the Zmat material configuration in the inp file
		sed -i -e 's/material=Elastic-Plastic\s*$/material=${material_file_elastic_plastic}/' ${NewJobName}
		sed -i -e 's/material=Elastic\s*$/material=${material_file_elastic}/' ${NewJobName}
		#sed -i -e 's/material=Elastic-Rigid\s*$/material=material_model_elastic.zmat/' ${NewJobName}
		materials_location=`grep -n '** MATERIALS' ${NewJobName} | awk -F ":" '{print $1}'`
		insertion_line=$(($materials_location+2))
		sed -i "${insertion_line}i **here" ${NewJobName}
		begin="**here"
		end="*Material, name=Elastic-Rigid"
		sed -i -e "/$begin/,/$end/{/$begin/{p; r material_def_inp.inp
			}; /$end/p; d}" ${NewJobName}
		sed -i '/**here/d' ${NewJobName}
		## Launch Job on Zmat
		# To configurate Zebulon with abaqus_6.11-2
		#source ~zebulon/Z8.7/do_config.sh 
		#Zmat cpus=12 memory=16gb $NewJobName
	done
	mkdir -p ${inp_folder}/${slip_suffix}/
	mv EP_* ${inp_folder}/${slip_suffix}/
	cp ${material_file_elastic} ${inp_folder}/${slip_suffix}/
	mv ${material_file_elastic_plastic} ${inp_folder}/${slip_suffix}/
done



