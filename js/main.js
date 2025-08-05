(function () {
  "use strict";

  var isMobile = {
    Android: function () {
      return navigator.userAgent.match(/Android/i);
    },
    BlackBerry: function () {
      return navigator.userAgent.match(/BlackBerry/i);
    },
    iOS: function () {
      return navigator.userAgent.match(/iPhone|iPad|iPod/i);
    },
    Opera: function () {
      return navigator.userAgent.match(/Opera Mini/i);
    },
    Windows: function () {
      return navigator.userAgent.match(/IEMobile/i);
    },
    any: function () {
      return (
        isMobile.Android() ||
        isMobile.BlackBerry() ||
        isMobile.iOS() ||
        isMobile.Opera() ||
        isMobile.Windows()
      );
    },
  };

  var fullHeight = function () {
    if (!isMobile.any()) {
      $(".js-fullheight").css("height", $(window).height());
      $(window).resize(function () {
        $(".js-fullheight").css("min-height", $(window).height());
      });
    }
  };

  // Animations

  var contentWayPoint = function () {
    var i = 0;
    $(".animate-box").waypoint(
      function (direction) {
        if (direction === "down" && !$(this.element).hasClass("animated")) {
          i++;

          $(this.element).addClass("item-animate");
          setTimeout(function () {
            $("body .animate-box.item-animate").each(function (k) {
              var el = $(this);
              setTimeout(
                function () {
                  var effect = el.data("animate-effect");
                  if (effect === "fadeIn") {
                    el.addClass("fadeIn animated");
                  } else if (effect === "fadeInLeft") {
                    el.addClass("fadeInLeft animated");
                  } else if (effect === "fadeInRight") {
                    el.addClass("fadeInRight animated");
                  } else {
                    el.addClass("fadeInUp animated");
                  }

                  el.removeClass("item-animate");
                },
                k * 200,
                "easeInOutExpo"
              );
            });
          }, 100);
        }
      },
      { offset: "85%" }
    );
  };

  var burgerMenu = function () {
    $(".js-nav-toggle").on("click", function (event) {
      event.preventDefault();
      var $this = $(this);

      if ($("body").hasClass("offcanvas")) {
        $this.removeClass("active");
        $("body").removeClass("offcanvas");
      } else {
        $this.addClass("active");
        $("body").addClass("offcanvas");
      }
    });
  };

  // Click outside of offcanvass
  var mobileMenuOutsideClick = function () {
    $(document).click(function (e) {
      var container = $("#aside, .js-nav-toggle");
      if (!container.is(e.target) && container.has(e.target).length === 0) {
        if ($("body").hasClass("offcanvas")) {
          $("body").removeClass("offcanvas");
          $(".js-nav-toggle").removeClass("active");
        }
      }
    });

    $(window).scroll(function () {
      if ($("body").hasClass("offcanvas")) {
        $("body").removeClass("offcanvas");
        $(".js-nav-toggle").removeClass("active");
      }
    });
  };

  var sliderMain = function () {
    $("#hero .flexslider").flexslider({
      animation: "fade",
      slideshowSpeed: 5000,
      directionNav: true,
      start: function () {
        setTimeout(function () {
          $(".slider-text").removeClass("animated fadeInUp");
          $(".flex-active-slide")
            .find(".slider-text")
            .addClass("animated fadeInUp");
        }, 500);
      },
      before: function () {
        setTimeout(function () {
          $(".slider-text").removeClass("animated fadeInUp");
          $(".flex-active-slide")
            .find(".slider-text")
            .addClass("animated fadeInUp");
        }, 500);
      },
    });
  };

  // Document on load.
  $(function () {
    fullHeight();
    contentWayPoint();
    burgerMenu();
    mobileMenuOutsideClick();
    sliderMain();
  });
})();
function copyCode(button) {
  const code = button.nextElementSibling.innerText;
  navigator.clipboard
    .writeText(code)
    .then(() => {
      button.textContent = "Copied!";
      setTimeout(() => (button.textContent = "Copy"), 1500);
    })
    .catch((err) => {
      console.error("Failed to copy!", err);
    });
}
function encodeEmail(email, key) {
  // Hex encode the key
  var encodedKey = key.toString(16);

  // ensure it is two digits long
  var encodedString = make2DigitsLong(encodedKey);

  // loop through every character in the email
  for (var n = 0; n < email.length; n++) {
    // Get the code (in decimal) for the nth character
    var charCode = email.charCodeAt(n);

    // XOR the character with the key
    var encoded = charCode ^ key;

    // Hex encode the result, and append to the output string
    var value = encoded.toString(16);
    encodedString += make2DigitsLong(value);
  }
  return encodedString;
}

function make2DigitsLong(value) {
  return value.length === 1 ? "0" + value : value;
}
function decodeEmail(encodedString) {
  var email = "";

  var keyInHex = encodedString.substr(0, 2);

  // Convert the hex-encoded key into decimal
  var key = parseInt(keyInHex, 16);

  // Loop through the remaining encoded characters in steps of 2
  for (var n = 2; n < encodedString.length; n += 2) {
    // Get the next pair of characters
    var charInHex = encodedString.substr(n, 2);

    // Convert hex to decimal
    var char = parseInt(charInHex, 16);

    // XOR the character with the key to get the original character
    var output = char ^ key;

    // Append the decoded character to the output
    email += String.fromCharCode(output);
  }
  return email;
}
// Find all the elements on the page that use class="eml-protected"
var allElements = document.getElementsByClassName("eml-protected");

// Loop through all the elements, and update them
for (var i = 0; i < allElements.length; i++) {
  updateAnchor(allElements[i]);
}

function updateAnchor(el) {
  // fetch the hex-encoded string
  var encoded = el.innerHTML;

  // decode the email, using the decodeEmail() function from before
  var decoded = decodeEmail(encoded);

  // Replace the text (displayed) content
  el.textContent = decoded;

  // Set the link to be a "mailto:" link
  el.href = "mailto:" + decoded;
}
function toggleTable(headerEl) {
  const arrow = headerEl.querySelector(".expand-arrow");
  const table = headerEl.nextElementSibling;

  arrow.classList.toggle("rotate");
  table.style.display = table.style.display === "table" ? "none" : "table";
}
function toggleCode(headerEl) {
  const arrow = headerEl.querySelector(".expand-arrow");
  const div = headerEl.nextElementSibling;

  arrow.classList.toggle("rotate");
  div.style.display = div.style.display === "block" ? "none" : "block";
}
document.addEventListener("DOMContentLoaded", function () {
  const toggleBtn = document.getElementById("toggle-contentbar");
  const contentbar = document.getElementById("contentbar");
  const arrow = toggleBtn.querySelector(".expand-arrow");

  toggleBtn.addEventListener("click", function () {
    arrow.classList.toggle("rotate");
    contentbar.classList.toggle("active");
  });
});
