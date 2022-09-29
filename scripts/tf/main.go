package main

import (
	"fmt"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmui/pkg/load"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmui/pkg/tmpl"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmui/pkg/vardef"
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
	//marshal, err := json.MarshalIndent(m, "", "  ")
	//if err != nil {
	//	return
	//}
	//fmt.Println(string(marshal))
	out := tmpl.ProcessTemplates(m, "lmc", "")
	//fmt.Println(out, "\n")
	outGlobal := tmpl.ProcessTemplatesGlobal(m, "lmc", "")
	//fmt.Println(outGlobal, "\n")

	tmplStr := fmt.Sprintf("%s\n%s", out, outGlobal)

	err = os.WriteFile(os.Args[2], []byte(tmplStr), os.ModePerm)
	varDef := vardef.ProcessVarDef(m, "")
	defs := vardef.Dump(varDef)

	err = os.WriteFile(os.Args[3], []byte(defs), os.ModePerm)
	//varDefGlobal := vardef.ProcessVarDefGlobal(m, "lmc", "")
	//fmt.Printf("%s\n\n", varDefGlobal)
	//fmt.Printf("%+v", varDef)
	//marshal, err := json.MarshalIndent(output, "", "  ")
	//if err != nil {
	//	return
	//}
	//fmt.Println(string(marshal))

}
