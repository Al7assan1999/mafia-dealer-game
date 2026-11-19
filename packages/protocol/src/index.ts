// The REST API's requests and answers, shared by the server (which validates with these) and the app.
import { z } from 'zod';

export const ROLES = ['', 'mafia', 'doctor', 'detective', 'citizen'] as const;
export const AVATAR_PRESETS = 10;
export const MAX_AVATAR_BYTES = 150_000;

export const Email = z.string().trim().toLowerCase().max(254).pipe(z.email());
export const Code = z.string().regex(/^\d{6}$/);
export const Device = z.string().trim().min(1).max(40);
/** Public @handle: 3-20 of A-Z a-z 0-9 _ . (unique, ignoring case). */
export const Handle = z.string().trim().transform(s => s.replace(/^@/, '')).pipe(z.string().regex(/^[A-Za-z0-9_.]{3,20}$/));
export const Display = z.string().trim().min(1).max(18);

export const EmailStart = z.object({ email: Email });
export const EmailVerify = z.object({ email: Email, code: Code, device: Device });
export const GoogleAuth = z.object({ idToken: z.string().min(20).max(4096), device: Device });
export const PatchMe = z.object({
  handle: Handle.optional(),
  display: Display.optional(),
  fav: z.enum(ROLES).optional(),
  showOnline: z.boolean().optional(),
}).strict();
/** A preset (0-9), or a photo as a data: URL (JPEG / PNG / WebP, cropped on the phone). */
export const PutAvatar = z.union([
  z.object({ preset: z.number().int().min(0).max(AVATAR_PRESETS - 1) }).strict(),
  z.object({ image: z.string().regex(/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/).max(Math.ceil(MAX_AVATAR_BYTES * 4 / 3) + 40) }).strict(),
]);
export const FriendRequest = z.object({ handle: Handle });

/** How another account is shown: never their email. rel: friends, requested (I asked), incoming (they asked), none, me. */
export type Rel = 'friends' | 'requested' | 'incoming' | 'none' | 'me';
export type Avatar = { preset: number } | { photo: number };
export interface UserCard { id: string; handle: string | null; display: string; avatar: Avatar; fav: string; rel: Rel }
export interface Me { id: string; handle: string | null; display: string; avatar: Avatar; fav: string; showOnline: boolean; emails: string[]; google: boolean }
export interface AuthAnswer { token: string; user: Me; needsHandle: boolean }
export interface SessionInfo { id: string; device: string; createdAt: number; lastSeenAt: number; current: boolean }
export interface FriendsAnswer { friends: UserCard[]; incoming: UserCard[]; outgoing: UserCard[] }

export type ApiError =
  | 'bad_request' | 'auth' | 'code' | 'slow_down' | 'google' | 'needs_handle' | 'handle_taken'
  | 'not_found' | 'self' | 'full' | 'no_request' | 'too_big';
