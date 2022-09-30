package load

import (
	"encoding/json"
	"io/ioutil"
)

func WalkSchema(path string) (map[string]any, error) {
	argusSchemaFile := path + "/values.schema.json"
	bytes, err := ioutil.ReadFile(argusSchemaFile)
	m := map[string]any{}
	if err == nil {
		err = json.Unmarshal(bytes, &m)
		if err != nil {
			return nil, err
		}
	}
	files, err := ioutil.ReadDir(path + "/charts")
	if err != nil {
		return m, nil
	}

	for _, f := range files {
		if f.IsDir() {
			schema, err := WalkSchema(path + "/charts/" + f.Name())
			if err != nil {
			}
			mv := m["properties"].(map[string]any)

			mv[f.Name()] = schema
		}
	}

	return m, nil
}
