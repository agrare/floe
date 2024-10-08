{
  "Comment": "Using Map state in Inline mode",
  "StartAt": "Pass",
  "States": {
    "Pass": {
      "Type": "Pass",
      "Next": "Map demo",
      "Result": {
        "foo": "bar",
        "colors": [
          "red",
          "green",
          "blue",
          "yellow",
          "white"
        ]
      }
    },
    "Map demo": {
      "Type": "Map",
      "ItemsPath": "$.colors",
      "MaxConcurrency": 2,
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "Generate UUID",
        "States": {
          "Generate UUID": {
            "Type": "Pass",
            "Next": "Sleep",
            "Parameters": {
              "uuid.$": "States.UUID()"
            }
          },
          "Sleep": {
            "Type": "Task",
            "Resource": "docker://docker.io/agrare/sleep:latest",
            "End": true
          }
        }
      },
      "End": true
    }
  }
}
