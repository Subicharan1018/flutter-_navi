import subprocess
import os
import sys

questions_file = "questions_list.txt"
output_file = "/home/subi/.gemini/antigravity-cli/brain/452af757-523a-4788-b53e-39efa32ef7f5/master_graphify_audit.md"

with open(questions_file, 'r') as f:
    questions = f.read().strip().split('\n')

with open(output_file, 'w') as out:
    out.write("# Master Graphify Query Output for 168 Audit Questions\n\n")
    for idx, q in enumerate(questions):
        q = q.strip()
        if not q:
            continue
        out.write(f"## {q}\n")
        out.write("```text\n")
        
        # Remove the number prefix for the query (e.g., "1. What..." -> "What...")
        query_text = q.split('. ', 1)[1] if '. ' in q else q
        
        print(f"Running query {idx+1}/{len(questions)}: {query_text[:50]}...")
        
        try:
            result = subprocess.run(['graphify', 'query', query_text], capture_output=True, text=True, timeout=10)
            output = result.stdout
            if not output.strip():
                output = "No graph nodes found or query yielded empty result.\n"
            out.write(output)
        except Exception as e:
            out.write(f"Error executing query: {e}\n")
            
        out.write("```\n\n")
        out.flush()

print(f"Finished writing to {output_file}")
