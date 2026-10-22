import type { SidefolkAPI } from "../shared/types";
declare global {
  interface Window {
    sidefolk?: SidefolkAPI;
  }
}
// The app explicitly renders launch instructions when the preload is absent.
export const api = window.sidefolk as SidefolkAPI;
