import re

def chunk_text(text: str, source_name: str, child_max_chars: int = 500):
    """
    Split text into hierarchical chunks based on Markdown headers.
    Returns a list of dicts: {
        "parent_content": str,
        "metadata": dict,
        "children": list[str]  # Leaf chunks to be embedded
    }
    """
    # 1. Split into sections by Markdown headers (#, ##, ###, ...)
    lines = text.splitlines()
    sections = []
    current_section = []
    current_headers = {1: None, 2: None, 3: None, 4: None, 5: None, 6: None}
    
    def get_header_path(headers):
        path = []
        for i in range(1, 7):
            if headers[i]:
                path.append(headers[i])
        return " > ".join(path) if path else "Root"

    for line in lines:
        header_match = re.match(r'^(#{1,6})\s+(.*)$', line)
        if header_match:
            # Save previous section if not empty
            if current_section:
                sections.append({
                    "content": "\n".join(current_section),
                    "header_path": get_header_path(current_headers)
                })
            
            # Update current headers
            level = len(header_match.group(1))
            current_headers[level] = header_match.group(2).strip()
            # Clear sub-headers
            for i in range(level + 1, 7):
                current_headers[i] = None
            
            current_section = [line]
        else:
            current_section.append(line)
            
    # Add last section
    if current_section:
        sections.append({
            "content": "\n".join(current_section),
            "header_path": get_header_path(current_headers)
        })

    # 2. Generate hierarchical structure
    hierarchical_chunks = []
    for section in sections:
        content = section["content"].strip()
        if not content:
            continue
            
        header_path = section["header_path"]
        
        # Split section content into smaller leaf chunks (children)
        children = []
        paragraphs = content.split("\n\n")
        current_child_buffer = []
        current_len = 0
        
        for para in paragraphs:
            # If a single paragraph is too large, we could split it further, 
            # but for now we split by paragraph for coherence.
            if current_len + len(para) + 2 > child_max_chars:
                if current_child_buffer:
                    children.append("\n\n".join(current_child_buffer))
                current_child_buffer = [para]
                current_len = len(para)
            else:
                current_child_buffer.append(para)
                current_len += len(para) + 2
        
        if current_child_buffer:
            children.append("\n\n".join(current_child_buffer))
            
        hierarchical_chunks.append({
            "parent_content": content,
            "metadata": {
                "header_path": header_path, 
                "source": source_name
            },
            "children": children
        })
                
    return hierarchical_chunks
