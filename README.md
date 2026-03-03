

Assumes you have access to a precompiled Edge binary with the enterprise feature turned on

Create a python venv and setup the requirements:

``` sh
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Start by running the `network-shenanigans.sh` script. This will create a local network namespace. This is to prevent Linux from doing a bunch
of clever things on localhost which make for unrealistic testing scenarios:

``` sh
sudo ./network-shenanigans.sh setup
```

Don't forget to tear it down when you're done!

``` sh
sudo ./network-shenanigans.sh cleanup

```

Start unleash and export an API key for Edge:

``` sh
export UNLEASH_API_KEY=*:development.15c9d1ee348d52d154ca17fa1cccd97034fe64b7aa1a034f2a546e4f
```

Spin up your Edge binary (this assumes it's located at ../../unleash-edge):

``` sh
sudo ip netns exec server_ns env UNLEASH_API_KEY="$UNLEASH_API_KEY" ../../unleash-edge/target/release/unleash-edge edge --streaming --upstream-url "http://10.200.1.1:4242" --tokens *:development.15c9d1ee348d52d154ca17fa1cccd97034fe64b7aa1a034f2a546e4f

```

Then start the tester (not explicit path to the venv, required for elevated permissions ala sudo here):

``` sh
sudo ip netns exec client_ns ./venv/bin/python main.py
```

You should see the script open some connections and do nothing. If it errors or crashes it's not working.

Once you're happy it's working you can run the schlurp script to execute this against a list of number of connections (10 50 200 500 1000 by default). If you want to run against more you'll very likely need to increase the ulimit on your box.

``` sh
./schlurp.sh
```

This will dump a results.csv of some memory stats. If you're a caveman like me and like pretty pictures, you can run the `show_me_the_money.py` script to get a graph

``` sh
python show_me_the_money.py && xdg-open kernel_buffers_linear.png && xdg-open edge_rss_linear.png && xdg-open tcp_mem_linear.png

```