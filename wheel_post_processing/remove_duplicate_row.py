import pandas as pd

# Load Excel file
input_file = "total_packages_to_process.xlsx"
output_file = "total_packages_to_process-duplicate-rm.xlsx"

df = pd.read_excel(input_file)

# Remove duplicates based on column C (wheel_name)
df_deduped = df.drop_duplicates(subset=["wheel_name"], keep="first")

# Save result
df_deduped.to_excel(output_file, index=False)

print(f"Duplicates removed. Output saved to {output_file}")
