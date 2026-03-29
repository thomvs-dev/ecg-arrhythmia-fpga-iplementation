import pymupdf
doc = pymupdf.open(r"c:\ACADEMICshi__\ecg-arrhythmia-fpga-iplementation\Round1_Submission_Format (1)-1.pdf")
for page in doc:
    print(f"=== PAGE {page.number + 1} ===")
    print(page.get_text())
doc.close()
