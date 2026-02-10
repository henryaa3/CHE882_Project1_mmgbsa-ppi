# CHE882_Project1_mmgbsa
mmgbsa for delta G value
# MM/GBSA (AmberTools MMPBSA.py) — 2GJJ Screen (First 25)

This workflow runs **MM/GBSA binding free energy estimates (ΔG, kcal/mol)** for **25 protein–protein complexes** on the MSU HPCC using **AmberTools** (`tleap` + `MMPBSA.py`).

It is designed as a **simple, non-PRODIGY** alternative that produces a numeric binding-affinity-style output (ΔG) from the complex PDBs you already generated.

---

## What this does

For each complex PDB (`pair_*.pdb`) it will:

1. **Split the complex PDB into two partners**
   - **Chain A** = receptor (2GJJ)
   - **Chain B** = partner protein
2. Build Amber topologies with `tleap` (protein force field ff14SB)
3. Run `MMPBSA.py` in **GB mode** on a **single snapshot** (the structure itself)
4. Write a CSV file:
   - `mmgbsa/results/mmgbsa_dG_25.csv`

---

## Requirements / Assumptions

### Inputs
- You are working in:
/mnt/gs21/scratch/$USER/boltz2_2GJJ_screen

- Your complex PDBs exist here:
prodigy_run/pdb/pair_*.pdb

- Each complex PDB contains **two chains** with IDs:
- `A` = receptor (2GJJ)
- `B` = partner

> If your chain IDs are not `A` and `B`, you must modify the chain-splitting function in `mmgbsa/run_mmgbsa_25.sh`.

### Software
- Miniforge module available on HPCC
- Conda environment will install:
- `ambertools`
- `python`

No GitHub cloning, no freesasa CLI, no PRODIGY required.

---

## Files created by the pipeline

After setup you will have:

- `mmgbsa/run_mmgbsa_25.sh`  
Main runner script (loops over 25 complexes and runs tleap + MMPBSA)

- `mmgbsa/run_mmgbsa_25.sbatch`  
SLURM script to submit the job

- `mmgbsa/results/mmgbsa_dG_25.csv`  
Output table of ΔG values (kcal/mol)

- `mmgbsa/logs/`  
Per-complex logs for `tleap` and `MMPBSA.py`

---

## Quick Start

### 1) Go to your screen folder
```bash
cd /mnt/gs21/scratch/$USER/boltz2_2GJJ_screen
2) Submit the job
If you already created the scripts:

sbatch mmgbsa/run_mmgbsa_25.sbatch
3) Check status
squeue -u $USER | grep mmgbsa_25 || true
4) View results
When finished:

column -s, -t mmgbsa/results/mmgbsa_dG_25.csv | head
Output Format
mmgbsa/results/mmgbsa_dG_25.csv looks like:

pair_id,deltaG_kcal_per_mol
pair_01_3H3B,-12.34
pair_02_6J71,-9.87
...
Values are ΔG estimates (kcal/mol) from MM/GBSA

More negative usually suggests stronger predicted binding (for ranking purposes)

Troubleshooting
1) ΔG shows NA
Most common reasons:

Chain splitting failed (complex doesn’t contain chain A and B)

tleap failed due to unusual residues, missing atoms, or non-protein components

Check logs for one pair:

tail -n 120 mmgbsa/logs/<pair>.tleap.log
tail -n 120 mmgbsa/logs/<pair>.mmpbsa.log
2) Confirm chain IDs in a complex
Pick one PDB and count chains:

p=mmgbsa/complex/pair_01_*.pdb
awk '$1=="ATOM"{print substr($0,22,1)}' "$p" | sort | uniq -c
You should see at least:

chain A

chain B

If not, update the splitter in mmgbsa/run_mmgbsa_25.sh to match your chain letters.

3) Job finishes but output CSV is missing
Check the SLURM log:

ls -lh mmgbsa/logs/mmgbsa_25-*.out mmgbsa/logs/mmgbsa_25-*.err
tail -n 200 mmgbsa/logs/mmgbsa_25-*.err
Notes on Interpretation
MM/GBSA is an approximate method; it’s mainly useful for relative ranking across your 25 complexes.

This pipeline uses a single snapshot (your predicted structure). If you later generate MD trajectories, MM/GBSA can be extended to multiple frames.

Reproducibility
To re-run cleanly:

rm -rf mmgbsa/results mmgbsa/work mmgbsa/logs
mkdir -p mmgbsa/results mmgbsa/work mmgbsa/logs
sbatch mmgbsa/run_mmgbsa_25.sbatch
Citation / Credit
If you need citations for a report:

AmberTools / MMPBSA.py (MM/GBSA)

ff14SB force field (used via tleap)

::contentReference[oaicite:0]{index=0}
