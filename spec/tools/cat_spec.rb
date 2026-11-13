require "setup"

Minitest.test "cat" do
  res = {ok: true, out: "hello\n", err: "", status: 0, truncated: false}

  tool = LLM::Tool::Unix::Cat.new.tap do |tool|
    allow(tool).to receive(:exec).and_return(res)
  end

  out = tool.call(paths: ["a.rb", "b.rb"])
  assert_equal(res, out)

  assert "builds the argument vector" do
    expect(tool).to have_received(:exec).with(
      command: "cat",
      arguments: ["--", "a.rb", "b.rb"],
      timeout: 5,
      max_bytes: 65024
    )
  end

  assert "adds flags to a file before the path" do
    out = tool.call(paths: ["a.rb"], number: true, squeeze_blank: true, show_ends: true)
    expect(tool).to have_received(:exec).with(
      command: "cat",
      arguments: ["-E", "-n", "-s", "--", "a.rb"],
      timeout: 5,
      max_bytes: 65024
    )
  end

  assert "forwards a timeout" do
    tool.call(paths: ["a.rb"], timeout: 10)
    expect(tool).to have_received(:exec).with(
      command: "cat",
      arguments: ["--", "a.rb"],
      timeout: 10,
      max_bytes: 65024
    )
  end

  assert "raises on no paths" do
    expect { tool.call(paths: []) }
      .to raise_error(RuntimeError, "paths must be one or more files")
  end

  assert "raises on an empty path" do
    expect { tool.call(paths: [""]) }
      .to raise_error(RuntimeError, "a path can't be empty")
  end

  assert "raises on a path of '-'" do
    expect { tool.call(paths: ["-"]) }
      .to raise_error(RuntimeError, "a path can't be '-' (that reads standard input)")
  end
end
