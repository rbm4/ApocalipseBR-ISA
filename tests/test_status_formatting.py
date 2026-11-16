"""Use exact B42 Translator methods to exercise percent labels, including its fallback."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATCH=ROOT.parent/'apocalipsebr-zomboid-patches'

class StatusFormattingTest(unittest.TestCase):
    def test_percent_templates_with_native_formatter(self):
        source=(PATCH/'42.22.2/decompiled/zombie/core/Translator.java').read_text(encoding='utf-8')
        def method(name):
            m=re.search(r'    private static [^\n]+ '+name+r'\([^\n]*\) \{.*?^    \}',source,re.S|re.M)
            self.assertIsNotNone(m,name)
            return m.group()
        pattern=re.search(r'    private static final Pattern FORMAT_TOKEN = [^\n]+',source).group()
        cases=[]
        for lang in ('EN','PTBR'):
            catalog=json.loads((ROOT/f'ApocalipseBR-ISA/42/media/lua/shared/Translate/{lang}/IG_UI.json').read_text(encoding='utf-8'))
            for key,value in catalog.items():
                if re.search(r'%[1-9]%+',value):
                    cases.append(f'check({json.dumps(lang+":"+key)}, {json.dumps(value,ensure_ascii=True)});')
        self.assertGreaterEqual(len(cases),10)
        harness='''import java.util.*; import java.util.regex.*;
public class NativeStatusFormatter {
    static class Core { static boolean IS_DEV=false; }
    enum LogSeverity { Warning }
    static class DebugType {
        static Logger General=new Logger();
        static class Logger {
            int errors;
            void printException(Throwable e,LogSeverity severity,String text) { errors++; }
            void printStackTrace(LogSeverity s,int i,Object o) {}
        }
    }
    static void check(String key,String template) {
        DebugType.General.errors=0;
        String actual=reportMissingArgumentsFromPastAbuse(key,formatFixer(template),new Object[]{"97.6","85"});
        if(DebugType.General.errors!=0 || !actual.contains("97.6%") || actual.contains("$s") || actual.contains("%%"))
            throw new AssertionError(key+": "+actual);
    }
'''+pattern+'\n'+method('formatFixer')+'\n'+method('fixupArgs')+'\n'+method('reportMissingArgumentsFromPastAbuse')+'''
    public static void main(String[] args) {
        String broken=reportMissingArgumentsFromPastAbuse("old",formatFixer("%1%"),new Object[]{"97.6"});
        if(!broken.equals("97.6$s%")) throw new AssertionError("Unexpected original reproduction: "+broken);
'''+ '\n'.join(cases)+'''\n    }
}
'''
        with tempfile.TemporaryDirectory(prefix='isa-status-format-') as d:
            path=Path(d)/'NativeStatusFormatter.java'
            path.write_text(harness,encoding='utf-8')
            subprocess.run([str(PATCH/'jdk/bin/javac.exe'),'-d',d,str(path)],check=True,capture_output=True,text=True)
            subprocess.run([str(PATCH/'jdk/bin/java.exe'),'-cp',d,'NativeStatusFormatter'],check=True,capture_output=True,text=True)

if __name__=='__main__': unittest.main()
