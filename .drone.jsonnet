local Pipeline(dist, dist_version, web_server, database) = {
  kind: "pipeline",
  steps: [
    {
      name: "build",
      image: dist + ":" + dist_version,
      environment: {
        WEB_SERVER: web_server,
        DATABASE: database,
      }
      commands: [
        "./run_test.sh",
      ]
    }
  ]
};

[
  Pipeline("debian", "jessie", "nginx", "mysql"),
  Pipeline("debian", "stretch", "nginx", "mysql"),
  Pipeline("debian", "buster", "nginx", "mysql"),
]