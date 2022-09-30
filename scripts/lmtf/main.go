package main

import (
	"fmt"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/load"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/tmpl"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/vardef"
	"os"
)

func main() {
	if len(os.Args) < 4 {
		fmt.Println("Insufficient params: <path> <tmpl file> <var file>")
		return
	}
	m, err := load.WalkSchema(os.Args[1])
	if err != nil {
		fmt.Println("chart directory doesn't exist")
	}
	out := tmpl.ProcessTemplates(m, "lmc", "")
	outGlobal := tmpl.ProcessTemplatesGlobal(m, "lmc", "")

	tmplStr := fmt.Sprintf("%s\n%s", out, outGlobal)

	err = os.WriteFile(os.Args[2], []byte(tmplStr), os.ModePerm)
	varDef := vardef.ProcessVarDef(m, "")
	defs := vardef.Dump(varDef)

	err = os.WriteFile(os.Args[3], []byte(defs), os.ModePerm)

}
