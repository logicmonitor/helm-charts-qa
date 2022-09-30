package main

import (
	"fmt"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/load"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/tmpl"
	"github.com/logicmonitor/helm-charts-qa/scripts/lmtf/pkg/vardef"
	"gopkg.in/yaml.v3"
	"io/ioutil"
	"os"
)

func main() {
	if len(os.Args) < 4 {
		fmt.Println("Insufficient params: <path> <tmpl file> <var file>")
		return
	}
	bytes, err := ioutil.ReadFile(os.Args[1] + "/Chart.yaml")
	cm := map[string]any{}
	if err == nil {
		err = yaml.Unmarshal(bytes, &cm)
		if err != nil {
			fmt.Printf("unable to read Chart.yaml to determine version: %s\n", err)
			return
		}
	}
	version := ""
	if v, ok := cm["version"]; ok {
		version = v.(string)
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

	defs = fmt.Sprintf("%s\nvariable \"lm_container_version\" {\n  type = string\n  default = \"%s\"\n}", defs, version)

	err = os.WriteFile(os.Args[3], []byte(defs), os.ModePerm)

}
