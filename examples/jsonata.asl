{
  "Comment": "An example of the JSONata query language. Run with: floe examples/jsonata.asl --input '{\"orders\": [{\"id\": 1, \"price\": 10, \"qty\": 3}, {\"id\": 2, \"price\": 5, \"qty\": 1}]}'",
  "QueryLanguage": "JSONata",
  "StartAt": "Total",
  "States": {
    "Total": {
      "Type": "Pass",
      "Comment": "Assign stores variables which are available to all later states",
      "Assign": {
        "orderCount": "{% $count($states.input.orders) %}",
        "total": "{% $sum($states.input.orders.(price * qty)) %}"
      },
      "Next": "CheckTotal"
    },
    "CheckTotal": {
      "Type": "Choice",
      "Choices": [
        {
          "Condition": "{% $total > 30 %}",
          "Next": "Large",
          "Output": {
            "size": "large"
          }
        }
      ],
      "Default": "Small"
    },
    "Large": {
      "Type": "Pass",
      "Output": {
        "size": "{% $states.input.size %}",
        "orders": "{% $orderCount %}",
        "total": "{% $total %}"
      },
      "End": true
    },
    "Small": {
      "Type": "Pass",
      "QueryLanguage": "JSONPath",
      "Comment": "A state can go back to JSONPath",
      "Parameters": {
        "size": "small",
        "orders.$": "$.orders"
      },
      "End": true
    }
  }
}
