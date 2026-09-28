import os
import zipfile

root_dir = r"c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\8122026\freedom-supercars-gcp"
zip_path = os.path.join(root_dir, "freedom_supercars_complete_codebase.zip")
doc_path = os.path.join(root_dir, "FREEDOM_SUPERCARS_FULL_CODEBASE.md")

exclude_dirs = {"node_modules", ".git", ".terraform", ".next", "dist", "build", "scratch"}
exclude_exts = {".zip", ".tar", ".gz", ".png", ".jpg", ".jpeg", ".pdf", ".vsix", ".ico", ".svg", ".lock"}
exclude_files = {"package-lock.json", "terraform.tfstate", "terraform.tfstate.backup"}

files_to_process = []
for dirpath, dirnames, filenames in os.walk(root_dir):
    dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
    for f in sorted(filenames):
        if f in exclude_files:
            continue
        ext = os.path.splitext(f)[1].lower()
        if ext in exclude_exts:
            continue
        if f.startswith("freedom_supercars_complete_codebase") or f.startswith("FREEDOM_SUPERCARS_FULL_CODEBASE"):
            continue
        full_path = os.path.join(dirpath, f)
        rel_path = os.path.relpath(full_path, root_dir)
        files_to_process.append((rel_path, full_path))

print(f"Total source files found: {len(files_to_process)}")

# 1. Create clean ZIP archive
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for rel_path, full_path in files_to_process:
        zf.write(full_path, rel_path)

zip_size = os.path.getsize(zip_path)
print(f"Zip created at: {zip_path} ({zip_size / 1024:.1f} KB)")

# 2. Create single consolidated master markdown file
with open(doc_path, "w", encoding="utf-8") as out:
    out.write("# Freedom Supercars GCP & Base44 - Complete Production Codebase Export\n\n")
    out.write(f"Generated on: 2026-09-28\n")
    out.write(f"Total Source Files: {len(files_to_process)}\n\n")
    out.write("## Table of Contents\n\n")
    for rel_path, full_path in files_to_process:
        size = os.path.getsize(full_path)
        anchor = rel_path.replace(os.sep, "-").replace(".", "-").lower()
        out.write(f"- [{rel_path}](#{anchor}) ({size:,} bytes)\n")
    out.write("\n---\n\n")
    
    lang_map = {
        ".js": "javascript", ".jsx": "jsx", ".ts": "typescript", ".tsx": "tsx",
        ".sql": "sql", ".json": "json", ".tf": "hcl", ".html": "html",
        ".css": "css", ".md": "markdown", ".py": "python", ".env": "bash",
        ".dockerignore": "text", ".gitignore": "text", "Dockerfile": "dockerfile"
    }
    
    for rel_path, full_path in files_to_process:
        anchor = rel_path.replace(os.sep, "-").replace(".", "-").lower()
        size = os.path.getsize(full_path)
        out.write(f"## {rel_path}\n\n")
        out.write(f"**File Path**: `{rel_path}` | **Size**: {size:,} bytes\n\n")
        ext = os.path.splitext(rel_path)[1].lower()
        lang = lang_map.get(ext, "")
        if "dockerfile" in rel_path.lower():
            lang = "dockerfile"
            
        out.write(f"```{lang}\n")
        try:
            with open(full_path, "r", encoding="utf-8", errors="replace") as infile:
                out.write(infile.read())
        except Exception as e:
            out.write(f"Error reading file: {e}")
        out.write("\n```\n\n---\n\n")

doc_size = os.path.getsize(doc_path)
print(f"Master Markdown created at: {doc_path} ({doc_size / 1024:.1f} KB)")
