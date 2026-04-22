################################################################################
# MM/GBSA (AmberTools MMPBSA.py) pipeline for 25 protein-protein complexes
# Assumes complex PDBs are in: prodigy_run/pdb/pair_*.pdb
# Assumes chains: A = receptor (2GJJ), B = partner
# Working dir: /mnt/gs21/scratch/$USER/boltz2_2GJJ_screen
################################################################################

# 0) cd to project
cd /mnt/gs21/scratch/$USER/boltz2_2GJJ_screen

# 1) Create conda env with AmberTools
module purge
module load Miniforge3
source "$(conda info --base)/etc/profile.d/conda.sh"

conda create -y -n mmpbsa -c conda-forge ambertools python=3.10
conda activate mmpbsa

# 2) Create folders
mkdir -p mmgbsa/{complex,rec,lig,work,results,logs}

# 3) Copy complexes into one place
cp prodigy_run/pdb/pair_*.pdb mmgbsa/complex/

# 4) Limit to first 25 (by filename order)
ls mmgbsa/complex/pair_*.pdb | head -n 25 > mmgbsa/pairs_25.list

# 5) Create the main runner script
cat > mmgbsa/run_mmgbsa_25.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)/mmgbsa"
LIST="$ROOT/pairs_25.list"

# MMGBSA control file (single-trajectory GB; single snapshot)
cat > "$ROOT/mmpbsa.in" <<'EOF'
&general
  startframe=1, endframe=1, interval=1,
  verbose=1,
/
&gb
  igb=5,
/
EOF

# split complex into chain A (receptor) and chain B (ligand/partner)
split_chains () {
  local in="$1" outA="$2" outB="$3"
  awk '($1=="ATOM" || $1=="HETATM"){
        ch=substr($0,22,1);
        if(ch=="A") print > outA;
        else if(ch=="B") print > outB;
       }' outA="$outA" outB="$outB" "$in"
}

# extract DELTA TOTAL from FINAL_RESULTS_MMPBSA.dat
extract_dg () {
  local f="$1"
  awk '/DELTA TOTAL/ {print $3; exit}' "$f"
}

echo "pair_id,deltaG_kcal_per_mol" > "$ROOT/results/mmgbsa_dG_25.csv"

n=0
while read -r pdb; do
  n=$((n+1))
  base="$(basename "$pdb" .pdb)"
  echo "==> [$n] $base"

  cplx="$ROOT/complex/${base}.pdb"
  rec="$ROOT/rec/${base}_rec.pdb"
  lig="$ROOT/lig/${base}_lig.pdb"
  work="$ROOT/work/$base"
  mkdir -p "$work"

  # split chains
  : > "$rec"
  : > "$lig"
  split_chains "$cplx" "$rec" "$lig"

  # sanity: ensure both have atoms
  if ! grep -q '^ATOM' "$rec" || ! grep -q '^ATOM' "$lig"; then
    echo "$base,NA" >> "$ROOT/results/mmgbsa_dG_25.csv"
    echo "WARN: chain split failed (need chains A/B). Skipping $base" | tee "$ROOT/logs/${base}.warn"
    continue
  fi

  # build prmtops with tleap (protein ff14SB)
  cat > "$work/leap.in" <<EOF
source leaprc.protein.ff14SB
set default PBRadii mbondi2
complex = loadpdb $cplx
receptor = loadpdb $rec
ligand = loadpdb $lig
saveamberparm complex $work/complex.prmtop $work/complex.inpcrd
saveamberparm receptor $work/receptor.prmtop $work/receptor.inpcrd
saveamberparm ligand $work/ligand.prmtop $work/ligand.inpcrd
quit
EOF

  tleap -f "$work/leap.in" > "$ROOT/logs/${base}.tleap.log" 2>&1

  # run MMPBSA on the single snapshot from complex.inpcrd
  (cd "$work" && MMPBSA.py -O \
     -i "$ROOT/mmpbsa.in" \
     -cp complex.prmtop -rp receptor.prmtop -lp ligand.prmtop \
     -y complex.inpcrd \
     > "$ROOT/logs/${base}.mmpbsa.log" 2>&1)

  res="$work/FINAL_RESULTS_MMPBSA.dat"
  if [[ -f "$res" ]]; then
    dg="$(extract_dg "$res" || true)"
    dg="${dg:-NA}"
  else
    dg="NA"
  fi

  echo "$base,$dg" >> "$ROOT/results/mmgbsa_dG_25.csv"

done < "$LIST"

echo "Wrote: $ROOT/results/mmgbsa_dG_25.csv"
BASH

chmod +x mmgbsa/run_mmgbsa_25.sh

# 6) Create the SLURM submit script
cat > mmgbsa/run_mmgbsa_25.sbatch <<'SBATCH'
#!/bin/bash --login
#SBATCH --job-name=mmgbsa_25
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=mmgbsa/logs/%x-%j.out
#SBATCH --error=mmgbsa/logs/%x-%j.err

module purge
module load Miniforge3
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate mmpbsa

cd /mnt/gs21/scratch/$USER/boltz2_2GJJ_screen
bash mmgbsa/run_mmgbsa_25.sh
SBATCH

# 7) Submit job
sbatch mmgbsa/run_mmgbsa_25.sbatch

# 8) Check job status
squeue -u $USER | grep mmgbsa_25 || true

# 9) When finished, view results
column -s, -t mmgbsa/results/mmgbsa_dG_25.csv | head
