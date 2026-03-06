GoldAdvisor Mats Scan Document (Ranked)

- This JSON contains ONLY mats from the goldmaking spreadsheet.
- Items are grouped by baseName.
- Ranks are assigned by ascending itemID within each baseName:
  rank 1 = lowest itemID, rank 2 = next higher itemID, etc.

Suggested scan iteration:
for each item in items:
  for each rankEntry in item.ranks (ascending):
    scan AH for rankEntry.itemID
  store results keyed by baseName + rank

If you need a single 'best available' per baseName:
  prefer highest rank that has an AH listing (or fallback to rank 1).

Files:
- goldadvisor_mats_ranked.json (authoritative)
- goldadvisor_mats_flat.tsv (human-friendly check)
