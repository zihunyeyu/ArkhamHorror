#!/usr/bin/env python3
"""
更新 local-files.json 文件，遍历 frontend/public/img/arkham/ 目录下的所有资源文件
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path


def update_local_files_json():
    # 项目根目录（脚本在 scripts/ 目录下）
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    
    # 资源目录和输出文件路径
    assets_dir = project_root / "frontend" / "public" / "img" / "arkham"
    output_file = project_root / "frontend" / "src" / "local-files.json"
    
    if not assets_dir.exists():
        print(f"错误: 资源目录不存在: {assets_dir}")
        return False
    
    # 收集所有文件路径（相对于 arkham/ 目录）
    files = []
    
    for root, dirs, filenames in os.walk(assets_dir):
        # 跳过隐藏目录
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for filename in filenames:
            # 跳过隐藏文件和特定文件
            if filename.startswith('.'):
                continue
            
            # 计算相对路径
            full_path = Path(root) / filename
            relative_path = full_path.relative_to(assets_dir)
            
            # 使用正斜杠作为路径分隔符（跨平台兼容）
            files.append(str(relative_path).replace(os.sep, '/'))
    
    # 按字母顺序排序
    files.sort()
    
    # 生成输出数据
    output_data = {
        "generatedAt": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        "count": len(files),
        "files": files
    }
    
    # 写入 JSON 文件（格式化输出，保持 2 空格缩进）
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output_data, f, indent=2, ensure_ascii=False)
        f.write('\n')  # 文件末尾添加换行
    
    print(f"已更新: {output_file}")
    print(f"共找到 {len(files)} 个文件")
    
    # 显示前 10 个和后 5 个文件作为预览
    if files:
        print("\n前 10 个文件:")
        for f in files[:10]:
            print(f"  - {f}")
        if len(files) > 15:
            print(f"  ... 还有 {len(files) - 15} 个文件 ...")
        print("\n后 5 个文件:")
        for f in files[-5:]:
            print(f"  - {f}")
    
    return True


if __name__ == "__main__":
    success = update_local_files_json()
    exit(0 if success else 1)
